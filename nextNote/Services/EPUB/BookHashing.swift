import Foundation
import CryptoKit

// Shared file-content SHA-256 helper for the book importers. Both EPUB and
// PDF import dedupe on the same hash; this lives outside the importers so
// they can't drift apart on the streaming chunk size or the digest format.
enum BookHashing {
    /// Stream the file in 64 KiB chunks so multi-hundred-MB PDFs / EPUBs
    /// don't get loaded fully into memory just to compute a dedupe hash.
    nonisolated static func fileSHA256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 16) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
