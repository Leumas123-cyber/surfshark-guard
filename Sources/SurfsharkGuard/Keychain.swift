import Foundation
import Security

/// Generic-password item for the qBittorrent Web UI password.
/// Stays on this Mac (`ThisDeviceOnly`) and is not written to UserDefaults.
enum KeychainStore {
    static let service = "app.surfsharkguard.webui"
    static let account = "password"
    static let defaultsLegacyKey = "webuiPass"

    static func loadPassword() -> String? {
        loadPassword(service: service, account: account)
    }

    static func loadPassword(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func savePassword(_ password: String) -> Bool {
        savePassword(password, service: service, account: account)
    }

    @discardableResult
    static func savePassword(_ password: String, service: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable as String] = false
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func deletePassword() {
        deletePassword(service: service, account: account)
    }

    static func deletePassword(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Move a leftover UserDefaults password into the Keychain, then wipe the default.
    static func migrateFromUserDefaults(_ defaults: UserDefaults) -> String {
        migrateFromUserDefaults(defaults, service: service, account: account)
    }

    static func migrateFromUserDefaults(_ defaults: UserDefaults,
                                        service: String,
                                        account: String) -> String {
        if let existing = loadPassword(service: service, account: account), !existing.isEmpty {
            if defaults.object(forKey: defaultsLegacyKey) != nil {
                defaults.removeObject(forKey: defaultsLegacyKey)
            }
            return existing
        }
        if let legacy = defaults.string(forKey: defaultsLegacyKey), !legacy.isEmpty {
            _ = savePassword(legacy, service: service, account: account)
            defaults.removeObject(forKey: defaultsLegacyKey)
            return loadPassword(service: service, account: account) ?? legacy
        }
        defaults.removeObject(forKey: defaultsLegacyKey)
        return ""
    }
}
