import SwiftUI

#if os(macOS)
import AppKit

/// Resolve a SwiftUI-named font into a concrete NSFont. Falls back to a
/// monospaced system font if the named typeface isn't installed.
func resolveFont(name: String, size: CGFloat) -> NSFont {
    switch name {
    case "SF Mono":  return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case "SF Pro":   return NSFont.systemFont(ofSize: size)
    case "New York": return NSFont(name: "NewYorkMedium-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
    case "Menlo":    return NSFont(name: "Menlo-Regular", size: size)         ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case "Courier":  return NSFont(name: "Courier", size: size)               ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    default:         return NSFont(name: name, size: size)                    ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

func makeParagraphStyle(lineSpacing: CGFloat) -> NSMutableParagraphStyle {
    let s = NSMutableParagraphStyle()
    s.lineHeightMultiple = lineSpacing
    return s
}
#endif

#if os(iOS)
import UIKit

func resolveFont(name: String, size: CGFloat) -> UIFont {
    switch name {
    case "SF Mono":  return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case "SF Pro":   return UIFont.systemFont(ofSize: size)
    case "New York": return UIFont(name: "NewYorkMedium-Regular", size: size) ?? UIFont.systemFont(ofSize: size)
    case "Menlo":    return UIFont(name: "Menlo-Regular", size: size)         ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case "Courier":  return UIFont(name: "Courier", size: size)               ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    default:         return UIFont(name: name, size: size)                    ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

func makeParagraphStyle(lineSpacing: CGFloat) -> NSMutableParagraphStyle {
    let s = NSMutableParagraphStyle()
    s.lineHeightMultiple = lineSpacing
    return s
}
#endif
