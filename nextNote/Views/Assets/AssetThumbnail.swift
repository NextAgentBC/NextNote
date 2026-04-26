#if os(macOS)
import SwiftUI
import AppKit
import AVFoundation

/// Generates a reasonably-sized preview image without blocking the main
/// thread. Images use NSImage; videos sample multiple offsets to dodge
/// black intro frames; audio falls back to a placeholder icon.
struct AssetThumbnail: View {
    let asset: AssetCatalog.Asset
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .task(id: asset.url) {
            // Reset when the cell is reused for a different asset (shouldn't
            // happen with Identifiable + url-id but cheap insurance).
            image = nil
            image = await Self.thumbnail(for: asset)
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.12)
            Image(systemName: asset.kind.iconName)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
        }
    }

    private static func thumbnail(for asset: AssetCatalog.Asset) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            switch asset.kind {
            case .image:
                return NSImage(contentsOf: asset.url)
            case .video:
                let a = AVURLAsset(url: asset.url)
                let gen = AVAssetImageGenerator(asset: a)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 600, height: 600)
                gen.requestedTimeToleranceBefore = .positiveInfinity
                gen.requestedTimeToleranceAfter = .positiveInfinity

                let durSec = CMTimeGetSeconds(a.duration)
                var candidates: [Double] = [5, 2, 0.5]
                if durSec.isFinite, durSec > 0 {
                    candidates.insert(durSec * 0.1, at: 0)
                }

                for sec in candidates {
                    let time = CMTime(seconds: sec, preferredTimescale: 600)
                    guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else {
                        continue
                    }
                    if !isMostlyBlack(cg) {
                        return NSImage(cgImage: cg, size: .zero)
                    }
                }
                // All sampled frames were black — return the last frame
                // anyway so the cell at least shows something.
                let fallback = CMTime(seconds: 1.0, preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: fallback, actualTime: nil) {
                    return NSImage(cgImage: cg, size: .zero)
                }
                return nil
            case .audio:
                return nil
            }
        }.value
    }

    /// Quick-and-dirty blackness check: downsample to 16×16 8-bit grayscale
    /// and compute mean luminance. Anything under ~12/255 is treated as a
    /// black intro frame. Nonisolated so the detached Task above can call
    /// it without main-actor warnings.
    nonisolated private static func isMostlyBlack(_ image: CGImage) -> Bool {
        let w = 16, h = 16
        var bytes = [UInt8](repeating: 0, count: w * h)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &bytes,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let total = bytes.reduce(0) { $0 + Int($1) }
        let mean = Double(total) / Double(w * h)
        return mean < 12.0
    }
}
#endif
