import Foundation

enum FileDestinations {
    /// Return a non-colliding URL inside `dir` for `filename`. If a file with
    /// the same name already exists, append " (n)" before the extension.
    static func unique(for filename: String, in dir: URL) -> URL {
        let fm = FileManager.default
        let initial = dir.appendingPathComponent(filename)
        if !fm.fileExists(atPath: initial.path) { return initial }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty
                ? "\(base) (\(n))"
                : "\(base) (\(n)).\(ext)"
            let url = dir.appendingPathComponent(candidate)
            if !fm.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    /// Variant that takes pre-split base + ext. Convenience for callers that
    /// already parsed the filename.
    static func unique(base: String, ext: String, in dir: URL) -> URL {
        let filename = ext.isEmpty ? base : "\(base).\(ext)"
        return unique(for: filename, in: dir)
    }
}
