import Foundation
import Security

/// Manages the Postgres DSN for the vector DB. The full DSN (containing the
/// password) is stored in Keychain so it's not in UserDefaults.
final class VectorDBSettings: @unchecked Sendable {
    static let shared = VectorDBSettings()

    private let keychainService = "com.nextnote.app"
    private let keychainAccount = "vectorDSN"
    private let defaultsKey = "nextnote.vectorDB.hasCustomDSN"

    var dsn: String {
        get { keychainDSN ?? AIProvider.localTailnet.vectorDSN ?? "" }
        set { storeInKeychain(newValue) }
    }

    private var keychainDSN: String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    private func storeInKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    func clearCustomDSN() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
