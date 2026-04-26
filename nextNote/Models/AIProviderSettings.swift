import Foundation
import Security

@MainActor
final class AIProviderSettings: ObservableObject {
    static let shared = AIProviderSettings()

    @Published var activeProvider: AIProvider {
        didSet { persist() }
    }

    private static let defaultsKey = "ai.activeProvider"
    private static let keychainService = "com.nextnote.ai"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(AIProvider.self, from: data) {
            activeProvider = decoded
        } else {
            activeProvider = .localTailnet
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(activeProvider) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func apiKey(for provider: AIProvider) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: provider.id.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        guard let data = key.data(using: .utf8) else { return }
        let account = provider.id.uuidString

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: account
        ]
        let update: [CFString: Any] = [kSecValueData: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clearAPIKey(for provider: AIProvider) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.keychainService,
            kSecAttrAccount: provider.id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
