import Foundation
import Security

/// Storage for credentials that must not land in the preferences plist.
protocol SecretStore {
    func string(forAccount account: String) -> String?
    /// Stores `value`, or removes the item when `value` is empty. Returns false if the write failed.
    @discardableResult
    func set(_ value: String, forAccount account: String) -> Bool
}

/// Generic-password items in the login keychain. Uses the file-based keychain rather than the
/// data protection one, which needs a signed app with a keychain access group and so would fail
/// for the unsigned SwiftPM build. A sandboxed app can read and write its own items without
/// extra entitlements.
struct KeychainStore: SecretStore {
    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "Poolser") {
        self.service = service
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
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
