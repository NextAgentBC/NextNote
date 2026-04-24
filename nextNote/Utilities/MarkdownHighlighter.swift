import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum MarkdownHighlighter {

    // MARK: - macOS

    #if os(macOS)
    static func highlightMac(_ text: String, fontSize: CGFloat) -> NSMutableAttributedString {
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.textColor,
            ]
        )

        let fullRange = NSRange(location: 0, length: attributed.length)

        // H1
        applyRegex(#"^# .+$"#, to: attributed, in: fullRange, attrs: [
            .font: NSFont.systemFont(ofSize: fontSize * 1.8, weight: .bold),
            .foregroundColor: NSColor.textColor,
        ])
        // H2
        applyRegex(#"^## .+$"#, to: attributed, in: fullRange, attrs: [
            .font: NSFont.systemFont(ofSize: fontSize * 1.5, weight: .bold),
            .foregroundColor: NSColor.textColor,
        ])
        // H3
        applyRegex(#"^### .+$"#, to: attributed, in: fullRange, attrs: [
            .font: NSFont.systemFont(ofSize: fontSize * 1.25, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        // Bold **text**
        applyRegex(#"\*\*(.+?)\*\*"#, to: attributed, in: fullRange, attrs: [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
        ])
        // Italic *text*
        applyRegex(#"(?<!\*)\*([^*]+)\*(?!\*)"#, to: attributed, in: fullRange, attrs: [
            .font: NSFontManager.shared.convert(
                NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                toHaveTrait: .italicFontMask
            ),
        ])
        // Strikethrough ~~text~~
        applyRegex(#"~~(.+?)~~"#, to: attributed, in: fullRange, attrs: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        // Inline code `text`
        applyRegex(#"`([^`]+)`"#, to: attributed, in: fullRange, attrs: [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize * 0.9, weight: .medium),
            .foregroundColor: NSColor.systemPink,
            .backgroundColor: NSColor.quaternaryLabelColor,
        ])
        // Code block markers ```
        applyRegex(#"^```.*$"#, to: attributed, in: fullRange, attrs: [
            .foregroundColor: NSColor.tertiaryLabelColor,
            .font: NSFont.monospacedSystemFont(ofSize: fontSize * 0.85, weight: .regular),
        ])
        // Links [text](url)
        applyRegex(#"\[([^\]]+)\]\([^\)]+\)"#, to: attributed, in: fullRange, attrs: [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        // Blockquote > text
        applyRegex(#"^> .+$"#, to: attributed, in: fullRange, attrs: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: fontSize),
                toHaveTrait: .italicFontMask
            ),
        ])
        // List items - text
        applyRegex(#"^[\s]*[-*+] .+$"#, to: attributed, in: fullRange, attrs: [
            .foregroundColor: NSColor.textColor,
        ])
        // Horizontal rule ---
        applyRegex(#"^-{3,}$"#, to: attributed, in: fullRange, attrs: [
            .foregroundColor: NSColor.separatorColor,
        ])

        return attributed
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    static func highlight(_ text: String, fontSize: CGFloat) -> NSMutableAttributedString {
        let baseFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: UIColor.label,
            ]
        )

        let fullRange = NSRange(location: 0, length: attributed.length)

        // H1
        applyRegex(#"^# .+$"#, to: attributed, in: fullRange, attrs: [
            .font: UIFont.systemFont(ofSize: fontSize * 1.8, weight: .bold),
        ])
        // H2
        applyRegex(#"^## .+$"#, to: attributed, in: fullRange, attrs: [
            .font: UIFont.systemFont(ofSize: fontSize * 1.5, weight: .bold),
        ])
        // H3
        applyRegex(#"^### .+$"#, to: attributed, in: fullRange, attrs: [
            .font: UIFont.systemFont(ofSize: fontSize * 1.25, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel,
        ])
        // Bold
        applyRegex(#"\*\*(.+?)\*\*"#, to: attributed, in: fullRange, attrs: [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
        ])
        // Italic
        applyRegex(#"(?<!\*)\*([^*]+)\*(?!\*)"#, to: attributed, in: fullRange, attrs: [
            .font: UIFont.italicSystemFont(ofSize: fontSize),
        ])
        // Strikethrough
        applyRegex(#"~~(.+?)~~"#, to: attributed, in: fullRange, attrs: [
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: UIColor.secondaryLabel,
        ])
        // Inline code
        applyRegex(#"`([^`]+)`"#, to: attributed, in: fullRange, attrs: [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize * 0.9, weight: .medium),
            .foregroundColor: UIColor.systemPink,
            .backgroundColor: UIColor.systemGray6,
        ])
        // Code block markers
        applyRegex(#"^```.*$"#, to: attributed, in: fullRange, attrs: [
            .foregroundColor: UIColor.tertiaryLabel,
        ])
        // Links
        applyRegex(#"\[([^\]]+)\]\([^\)]+\)"#, to: attributed, in: fullRange, attrs: [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        // Blockquote
        applyRegex(#"^> .+$"#, to: attributed, in: fullRange, attrs: [
            .foregroundColor: UIColor.secondaryLabel,
            .font: UIFont.italicSystemFont(ofSize: fontSize),
        ])
        // Horizontal rule
        applyRegex(#"^-{3,}$"#, to: attributed, in: fullRange, attrs: [
            .foregroundColor: UIColor.separator,
        ])

        return attributed
    }
    #endif

    // MARK: - Shared Helper

    private static func applyRegex(
        _ pattern: String,
        to attributed: NSMutableAttributedString,
        in range: NSRange,
        attrs: [NSAttributedString.Key: Any]
    ) {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines]
        ) else { return }

        for match in regex.matches(in: attributed.string, range: range) {
            attributed.addAttributes(attrs, range: match.range)
        }
    }
}
