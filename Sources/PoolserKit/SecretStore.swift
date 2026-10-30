import Foundation
import Security

/// Storage for credentials that must not land in the preferences plist.
protocol SecretStore {
    func string(forAccount account: String) -> String?
    /// Stores `value`, or removes the item when `value` is empty. Returns false if the write failed.
    @discardableResult
    func set(_ value: String, forAccount account: String) -> Bool
}

/// Generic-password items. macOS keeps the file-based login keychain for unsigned SwiftPM builds;
/// iOS uses the access group shared by its app and widget.
struct KeychainStore: SecretStore {
    let service: String
    let accessGroup: String?

    init(service: String? = nil) {
        #if os(iOS)
        self.service = service ?? "PoolserIOS"
        accessGroup = Bundle.main.object(forInfoDictionaryKey: "PoolserKeychainGroup") as? String
        #else
        self.service = service ?? Bundle.main.bundleIdentifier ?? "Poolser"
        accessGroup = nil
        #endif
    }

    func string(forAccount account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func set(_ value: String, forAccount account: String) -> Bool {
        let query = baseQuery(account: account)
        guard !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        // Update in place so the item keeps its access control list.
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status != errSecItemNotFound { return status == errSecSuccess }
        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
