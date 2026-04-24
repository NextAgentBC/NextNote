import Foundation

// Runs yt-dlp as a subprocess and streams its stdout to parse progress and
// capture the final output filepath. Both audio and video modes pick a
// single-file format so the user doesn't need ffmpeg installed.
//
// Output detection relies on `--print after_move:filepath` which yt-dlp
// prints once per downloaded file, after all renames/moves complete.
// Cancellation handle — caller keeps a reference so the UI Cancel button can
// terminate the subprocess mid-flight.
final class YTDLPHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private(set) var cancelled: Bool = false

    func attach(_ p: Process) {
        lock.lock(); defer { lock.unlock() }
        process = p
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        process?.terminate()
    }
}

enum YTDLPDownloader {

    /// Video resolution cap. YouTube only ships H.264 up to 1080p — higher
    /// tiers come as VP9 or AV1, which modern AVFoundation decodes natively
    /// on macOS 14+ (AV1 needs an M3 chip). Picker exposes common steps; the
    /// selector hands yt-dlp a height cap + preference for H.264 when a match
    /// exists at that resolution.
    enum Quality: String, CaseIterable, Identifiable, Sendable {
        case best     = "Best"
        case uhd2160  = "2160p (4K)"
        case qhd1440  = "1440p"
        case fhd1080  = "1080p"
        case hd720    = "720p"
        case sd480    = "480p"

        var id: String { rawValue }

        /// nil = no cap (best available).
        var heightCap: Int? {
            switch self {
            case .best: return nil
            case .uhd2160: return 2160
            case .qhd1440: return 1440
            case .fhd1080: return 1080
            case .hd720: return 720
            case .sd480: return 480
            }
        }
    }

    enum Mode {
        case audio
        case video

        /// Format selector. When ffmpeg is available we can merge separate
        /// bestvideo + bestaudio streams, which is required to reach YouTube's
        /// higher-res tiers (1080p+ never ship pre-muxed). Without ffmpeg we
        /// fall back to single-file "best", capped by what YT pre-muxes.
        func formatArgs(hasFFmpeg: Bool, quality: Quality) -> [String] {
            switch self {
            case .audio:
                if hasFFmpeg {
                    return [
                        "-f", "bestaudio/best",
                        "-x",
                        "--audio-format", "mp3",
                        "--audio-quality", "0",
                    ]
                } else {
                    return ["-f", "bestaudio[ext=m4a]/bestaudio"]
                }
            case .video:
                if hasFFmpeg {
                    // --format-sort ranks candidate streams: highest resolution
                    // first, then prefer H.264 (best AVFoundation compat + HW
                    // decode on every Mac), then AAC audio, then mp4 container.
                    // yt-dlp picks the top-ranked stream that satisfies -f.
                    let sort = "res,vcodec:h264,acodec:aac,ext:mp4"
                    let selector: String
                    if let cap = quality.heightCap {
                        selector = "bv*[height<=\(cap)]+ba/b[height<=\(cap)]/bv*+ba/b"
                    } else {
                        selector = "bv*+ba/b"
                    }
                    return [
                        "-S", sort,
                        "-f", selector,
                        "--merge-output-format", "mp4",
                    ]
                } else {
                    // No ffmpeg → pre-muxed mp4 only (YouTube caps these at
                    // 720p). Honor the user's cap if lower.
                    if let cap = quality.heightCap, cap < 720 {
                        return ["-f", "best[ext=mp4][height<=\(cap)]/best[height<=\(cap)]/best"]
                    }
                    return ["-f", "best[ext=mp4]/best"]
                }
            }
        }
    }

    enum DLError: LocalizedError {
        case launch(String)
        case nonZeroExit(Int32, String)
        case missingOutput

        var errorDescription: String? {
            switch self {
            case .launch(let m): return "Failed to launch yt-dlp: \(m)"
            case .nonZeroExit(let code, let tail):
                return "yt-dlp exited \(code). Tail: \(tail)"
            case .missingOutput:
                return "yt-dlp finished but no output path was captured."
            }
        }
    }

    /// Fields lifted from yt-dlp's metadata extraction. Null-ish values
    /// (yt-dlp prints "NA" when a field is missing) are normalized to nil.
    struct Metadata: Sendable {
        var title: String?
        var uploader: String?
        var channel: String?
        var categories: String?   // yt-dlp emits python-repr list, e.g. ['Music', 'Entertainment']
        var tags: String?
        var playlist: String?
        var duration: String?
        var uploadDate: String?

        var isEmpty: Bool {
            uploader == nil && channel == nil && categories == nil
                && tags == nil && playlist == nil
        }
    }

    struct Result: Sendable {
        let outputURL: URL
        let metadata: Metadata
    }

    /// Download `videoURL` into `folder`, streaming progress 0…1 via the
    /// `progress` closure. Returns the final on-disk URL.
    static func download(
        videoURL: String,
        mode: Mode,
        quality: Quality = .best,
        folder: URL,
        binary: URL,
        ffmpeg: URL? = nil,
        handle: YTDLPHandle? = nil,
        progress: @Sendable @escaping (Double, String) -> Void
    ) async throws -> Result {
        let process = Process()
        process.executableURL = binary
        process.currentDirectoryURL = folder
        handle?.attach(process)

        // --no-playlist:      strip list= from watch URLs.
        // --playlist-items 1: hard cap — even if the URL is a channel /
        //                     playlist page, fetch only the first video.
        //                     Prevents a "paste artist page → 200 files"
        //                     surprise.
        // --newline + --progress-template: machine-friendly progress.
        // --print after_move:filepath: emits final file path on success.
        // --restrict-filenames: ASCII-only names.
        var args: [String] = [
            "--no-playlist",
            "--playlist-items", "1",
            "--newline",
            "--progress-template", "PROGRESS|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.eta)s",
            // Each --print line emits once after the final move, prefixed so
            // we can demux them on stdout. Filepath stays prefix-less for
            // backward-compatible parsing below.
            "--print", "after_move:filepath",
            "--print", "after_move:METATITLE|%(title)s",
            "--print", "after_move:UPLOADER|%(uploader)s",
            "--print", "after_move:CHANNEL|%(channel)s",
            "--print", "after_move:CATEGORIES|%(categories)s",
            "--print", "after_move:TAGS|%(tags)s",
            "--print", "after_move:PLAYLIST|%(playlist)s",
            "--print", "after_move:DURATION|%(duration_string)s",
            "--print", "after_move:UPLOADDATE|%(upload_date)s",
            // No --restrict-filenames: macOS handles unicode filenames fine
            // and stripping to ASCII mangled Chinese / Japanese titles into
            // underscore pinyin ("邓紫棋 - 光年之外" → "G.E.M._LIGHT_YEAR..."),
            // hiding the real title from both the user and the classifier.
            // Replace any path separator (yt-dlp already guards ":" and "/")
            // via --replace-in-metadata as a safety net.
            "--replace-in-metadata", "title", "[/:\\\\]", "-",
            "-o", "%(uploader,channel|Unknown)s - %(title).80B [%(id)s].%(ext)s",
        ]
        args.append(contentsOf: mode.formatArgs(hasFFmpeg: ffmpeg != nil, quality: quality))
        if let ffmpeg {
            args.append(contentsOf: ["--ffmpeg-location", ffmpeg.path])
        }
        args.append(videoURL)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw DLError.launch(error.localizedDescription)
        }

        let output = StreamBox()
        let stderrOut = StreamBox()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            for line in chunk.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let lineStr = String(line)
                output.append(lineStr)
                if lineStr.hasPrefix("PROGRESS|") {
                    let parts = lineStr.split(separator: "|").map(String.init)
                    if parts.count >= 3,
                       let got = Double(parts[1]),
                       let total = Double(parts[2]),
                       total > 0 {
                        progress(got / total, "Downloading \(Int(got / total * 100))%")
                    }
                } else if !lineStr.isEmpty {
                    progress(-1, lineStr)
                }
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            stderrOut.append(chunk)
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let status = process.terminationStatus
        let allLines = output.lines

        // Demux prefixed print lines → metadata. yt-dlp emits "NA" for missing
        // fields; normalize those back to nil.
        func pick(_ prefix: String) -> String? {
            guard let line = allLines.last(where: { $0.hasPrefix(prefix + "|") }) else { return nil }
            let v = String(line.dropFirst(prefix.count + 1)).trimmingCharacters(in: .whitespaces)
            if v.isEmpty || v == "NA" || v == "None" { return nil }
            return v
        }
        let metadata = Metadata(
            title: pick("METATITLE"),
            uploader: pick("UPLOADER"),
            channel: pick("CHANNEL"),
            categories: pick("CATEGORIES"),
            tags: pick("TAGS"),
            playlist: pick("PLAYLIST"),
            duration: pick("DURATION"),
            uploadDate: pick("UPLOADDATE")
        )

        // `after_move:filepath` is printed bare, without any known prefix.
        // It's the last plain line that isn't a progress marker or a META line.
        let knownPrefixes = ["PROGRESS|", "METATITLE|", "UPLOADER|", "CHANNEL|",
                             "CATEGORIES|", "TAGS|", "PLAYLIST|", "DURATION|", "UPLOADDATE|"]
        let outputPathLine = allLines.reversed().first { line in
            !knownPrefixes.contains(where: { line.hasPrefix($0) }) &&
            !line.hasPrefix("[") &&
            !line.trimmingCharacters(in: .whitespaces).isEmpty
        }

        if handle?.cancelled == true {
            throw DLError.nonZeroExit(status, "Cancelled by user.")
        }
        guard status == 0 else {
            throw DLError.nonZeroExit(status, stderrOut.joined)
        }
        guard let path = outputPathLine?.trimmingCharacters(in: .whitespaces),
              !path.isEmpty else {
            throw DLError.missingOutput
        }

        // yt-dlp prints absolute path when run with an absolute cwd+output.
        // If the template happened to produce a relative path, resolve it
        // against the download folder.
        let url: URL
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = folder.appendingPathComponent(path)
        }

        // YouTube ships 1440p/4K only as VP9/AV1. AVPlayer on older/Intel Macs
        // can't decode those → silent video. Transcode to HEVC (hvc1) so
        // playback works everywhere. H.264 / HEVC stay untouched.
        let finalURL: URL
        if case .video = mode, let ffmpeg {
            finalURL = try await Transcoder.ensurePlayable(
                url: url,
                ffmpeg: ffmpeg,
                progress: progress
            )
        } else {
            finalURL = url
        }

        return Result(outputURL: finalURL, metadata: metadata)
    }

    // MARK: - Post-download codec normalization

    enum Transcoder {
        /// Codecs AVFoundation can always render on every Mac. Anything else
        /// (vp9, av1, …) gets re-encoded to HEVC via VideoToolbox HW encode.
        private static let playableCodecs: Set<String> = ["h264", "hevc", "h265"]

        static func ensurePlayable(
            url: URL,
            ffmpeg: URL,
            progress: @Sendable @escaping (Double, String) -> Void
        ) async throws -> URL {
            guard let codec = await probeVideoCodec(url: url, ffmpeg: ffmpeg) else {
                return url
            }
            if playableCodecs.contains(codec) { return url }

            progress(-1, "Transcoding \(codec) → HEVC for playback…")

            let tmp = url
                .deletingPathExtension()
                .appendingPathExtension("transcoding.mp4")
            try? FileManager.default.removeItem(at: tmp)

            let p = Process()
            p.executableURL = ffmpeg
            p.arguments = [
                "-y",
                "-hide_banner",
                "-nostats",
                "-nostdin",
                "-i", url.path,
                "-c:v", "hevc_videotoolbox",
                "-tag:v", "hvc1",
                "-q:v", "65",
                "-c:a", "copy",
                "-movflags", "+faststart",
                tmp.path,
            ]
            let errPipe = Pipe()
            p.standardError = errPipe
            p.standardOutput = Pipe()

            do {
                try p.run()
            } catch {
                throw DLError.launch("ffmpeg: \(error.localizedDescription)")
            }

            let errBox = StreamBox()
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let data = h.availableData
                guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
                errBox.append(s)
            }

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                p.terminationHandler = { _ in cont.resume() }
            }
            errPipe.fileHandleForReading.readabilityHandler = nil

            guard p.terminationStatus == 0 else {
                try? FileManager.default.removeItem(at: tmp)
                let tail = String(errBox.joined.suffix(500))
                throw DLError.nonZeroExit(p.terminationStatus, "Transcode failed: \(tail)")
            }

            // Replace original with transcoded copy. Keep same path so caller
            // (catalog, dedup, etc.) sees a single stable URL.
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tmp, to: url)
            return url
        }

        /// Parse `ffmpeg -i <file>` stderr for the first `Video:` stream's
        /// codec name. ffmpeg exits with status 1 (no output file) but always
        /// prints stream info to stderr first — that's what we want.
        private static func probeVideoCodec(url: URL, ffmpeg: URL) async -> String? {
            let p = Process()
            p.executableURL = ffmpeg
            p.arguments = ["-hide_banner", "-i", url.path]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            do { try p.run() } catch { return nil }

            let data = err.fileHandleForReading.readDataToEndOfFile()
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                p.terminationHandler = { _ in cont.resume() }
            }
            guard let text = String(data: data, encoding: .utf8) else { return nil }

            for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let line = String(rawLine)
                guard let r = line.range(of: "Video: ") else { continue }
                let after = line[r.upperBound...]
                let codec = after.prefix(while: { $0 != " " && $0 != "," })
                return codec.lowercased()
            }
            return nil
        }
    }

    // Thread-safe line collector for the readabilityHandler callbacks, which
    // fire on an arbitrary background queue.
    private final class StreamBox: @unchecked Sendable {
        private var buffer: [String] = []
        private let lock = NSLock()

        func append(_ line: String) {
            lock.lock(); defer { lock.unlock() }
            buffer.append(line)
        }

        var lines: [String] {
            lock.lock(); defer { lock.unlock() }
            return buffer
        }

        var joined: String {
            lock.lock(); defer { lock.unlock() }
            return buffer.joined(separator: "\n")
        }
    }
}
