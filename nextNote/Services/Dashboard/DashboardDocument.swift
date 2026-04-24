import Foundation

// Parser/serializer for the pinned-user + AI-generated split inside a
// `_dashboard.md`. Corruption-tolerant: if markers are missing or
// mismatched we treat everything as pinned and start fresh on next
// regen — never silently drop user text.
//
// Format (v=1):
//
//   <!-- nextNote:pinned:start v=1 -->
//   …user content…
//   <!-- nextNote:pinned:end -->
//   <!-- nextNote:ai:start v=1 generated=2026-04-21T12:00:00Z hash=abc123 -->
//   …AI content…
//   <!-- nextNote:ai:end -->
//
enum DashboardDocument {
    struct Parsed {
        var pinned: String
        var ai: String
        var aiGeneratedAt: Date?
        var aiInputHash: String?
        /// True when markers were absent or malformed; caller should not
        /// assume the AI block is authoritative. Regenerating is safe —
        /// the legacy content already ended up in `pinned`.
        var fallbackToPinned: Bool
    }

    private static let pinnedOpen = "<!-- nextNote:pinned:start"
    private static let pinnedClose = "<!-- nextNote:pinned:end -->"
    private static let aiOpen = "<!-- nextNote:ai:start"
    private static let aiClose = "<!-- nextNote:ai:end -->"

    static func parse(_ text: String) -> Parsed {
        // Empty or no markers: whole file → pinned
        guard
            let pinnedStart = range(of: pinnedOpen, in: text),
            let pinnedEnd = text.range(of: pinnedClose, range: pinnedStart.upperBound..<text.endIndex)
        else {
            return Parsed(pinned: text, ai: "", aiGeneratedAt: nil, aiInputHash: nil, fallbackToPinned: !text.isEmpty)
        }

        let pinnedOpenLineEnd = text.range(of: "-->", range: pinnedStart.upperBound..<text.endIndex)?.upperBound ?? pinnedStart.upperBound
        let pinned = String(text[pinnedOpenLineEnd..<pinnedEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // AI block optional
        guard
            let aiStart = text.range(of: aiOpen, range: pinnedEnd.upperBound..<text.endIndex),
            let aiHeaderEnd = text.range(of: "-->", range: aiStart.upperBound..<text.endIndex),
            let aiEnd = text.range(of: aiClose, range: aiHeaderEnd.upperBound..<text.endIndex)
        else {
            return Parsed(pinned: pinned, ai: "", aiGeneratedAt: nil, aiInputHash: nil, fallbackToPinned: false)
        }

        let header = String(text[aiStart.lowerBound..<aiHeaderEnd.upperBound])
        let aiBody = String(text[aiHeaderEnd.upperBound..<aiEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Parsed(
            pinned: pinned,
            ai: aiBody,
            aiGeneratedAt: extractDate(from: header),
            aiInputHash: extractHash(from: header),
            fallbackToPinned: false
        )
    }

    static func serialize(pinned: String, ai: String, aiInputHash: String, at date: Date = Date()) -> String {
        let iso = ISO8601DateFormatter().string(from: date)
        let trimmedPinned = pinned.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAI = ai.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
        <!-- nextNote:pinned:start v=1 -->
        \(trimmedPinned)
        <!-- nextNote:pinned:end -->
        <!-- nextNote:ai:start v=1 generated=\(iso) hash=\(aiInputHash) -->
        \(trimmedAI)
        <!-- nextNote:ai:end -->

        """
    }

    // MARK: - Helpers

    private static func range(of needle: String, in text: String) -> Range<String.Index>? {
        text.range(of: needle)
    }

    private static func extractDate(from header: String) -> Date? {
        guard let match = header.range(of: #"generated=([^\s>]+)"#, options: .regularExpression) else { return nil }
        let matchStr = String(header[match])
        let iso = matchStr.replacingOccurrences(of: "generated=", with: "")
        return ISO8601DateFormatter().date(from: iso)
    }

    private static func extractHash(from header: String) -> String? {
        guard let match = header.range(of: #"hash=([^\s>]+)"#, options: .regularExpression) else { return nil }
        return String(header[match]).replacingOccurrences(of: "hash=", with: "")
    }
}
