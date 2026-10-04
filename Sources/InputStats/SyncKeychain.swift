import Foundation
import Security
import LocalAuthentication

protocol SyncCredentialStore {
    func read(account: String, allowInteraction: Bool) throws -> String?
    func save(_ token: String, account: String) throws
    func remove(account: String) throws
}

struct SyncKeychain: SyncCredentialStore {
    private let service = "com.local.inputstats.github-sync"
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    func read(account: String, allowInteraction: Bool = true) throws -> String? {
        var query = query(account)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowInteraction {
            let context = LAContext(); context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw GitHubSyncError.keychain(status)
        }
        return token
    }
    func save(_ token: String, account: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account); item.merge(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw GitHubSyncError.keychain(status) }
    }
    func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GitHubSyncError.keychain(status) }
    }
}
