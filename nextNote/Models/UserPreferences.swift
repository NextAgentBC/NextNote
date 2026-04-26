import SwiftUI

@MainActor
final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    // MARK: - Appearance
    @AppStorage("themeMode") var themeMode: String = "system"
    @AppStorage("fontName") var fontName: String = "SF Mono"
    @AppStorage("fontSize") var fontSize: Double = 16
    @AppStorage("lineSpacing") var lineSpacing: Double = 1.4
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true

    // MARK: - Editor
    @AppStorage("autoSaveInterval") var autoSaveInterval: Int = 30
    @AppStorage("autoIndent") var autoIndent: Bool = true
    @AppStorage("tabWidth") var tabWidth: Int = 4
    @AppStorage("wrapLines") var wrapLines: Bool = true

    // MARK: - Default format for new documents
    @AppStorage("defaultFileType") var defaultFileType: String = FileType.txt.rawValue

    // MARK: - Sync
    @AppStorage("enableICloudSync") var enableICloudSync: Bool = false

    // MARK: - Vault (R0 redesign feature flag)
    // When false, app runs legacy flat SwiftData-backed document model.
    // When true, app runs new directory-backed vault model (R1+).
    // Default false until R2 migration lands and is verified on the user's data.
    @AppStorage("vaultMode") var vaultMode: Bool = true

    var editorFont: Font {
        .custom(fontName, size: fontSize)
    }

    private init() {}
}
