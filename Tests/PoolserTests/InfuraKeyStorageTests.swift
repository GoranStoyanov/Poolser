import Foundation
import Testing
@testable import PoolserKit

private final class InMemorySecretStore: SecretStore {
    var items: [String: String] = [:]
    var failWrites = false

    init(_ items: [String: String] = [:]) {
        self.items = items
    }

    func string(forAccount account: String) -> String? {
        items[account]
    }

    func set(_ value: String, forAccount account: String) -> Bool {
        guard !failWrites else { return false }
        items[account] = value.isEmpty ? nil : value
        return true
    }
}

private let account = AppSettings.infuraKeyAccount
private let key = "test-infura-key"

@Suite final class InfuraKeyMigrationTests {
    /// A throwaway defaults domain per test, so tests never touch the app's real preferences.
    private let suite = "PoolserTests.\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func movesKeyFromUserDefaultsToSecretStore() {
        defaults.set(key, forKey: "infuraAPIKey")
        let store = InMemorySecretStore()

        #expect(AppSettings.loadInfuraAPIKey(defaults: defaults, secrets: store) == key)
        #expect(store.items[account] == key)
        #expect(defaults.object(forKey: "infuraAPIKey") == nil)
    }

    @Test func extractsKeyFromLegacyRPCURL() {
        defaults.set("https://mainnet.infura.io/v3/\(key)", forKey: "rpcURL")
        let store = InMemorySecretStore()

        #expect(AppSettings.loadInfuraAPIKey(defaults: defaults, secrets: store) == key)
        #expect(store.items[account] == key)
        #expect(defaults.object(forKey: "rpcURL") == nil)
    }

    @Test func prefersInfuraKeyOverLegacyRPCURL() {
        defaults.set(key, forKey: "infuraAPIKey")
        defaults.set("https://mainnet.infura.io/v3/older", forKey: "rpcURL")
        let store = InMemorySecretStore()

        #expect(AppSettings.loadInfuraAPIKey(defaults: defaults, secrets: store) == key)
        #expect(defaults.object(forKey: "infuraAPIKey") == nil)
        #expect(defaults.object(forKey: "rpcURL") == nil)
    }

    @Test func keychainValueWinsAndStaleCopyIsRemoved() {
        defaults.set("stale", forKey: "infuraAPIKey")
        let store = InMemorySecretStore([account: key])

        #expect(AppSettings.loadInfuraAPIKey(defaults: defaults, secrets: store) == key)
        #expect(store.items[account] == key)
        #expect(defaults.object(forKey: "infuraAPIKey") == nil)
    }

    @Test func emptyLegacyValueIsRemovedWithoutWritingToStore() {
        defaults.set("", forKey: "infuraAPIKey")
        defaults.set("https://example.com/rpc", forKey: "rpcURL")
        let store = InMemorySecretStore()

        #expect(AppSettings.loadInfuraAPIKey(defaults: defaults, secrets: store) == "")
        #expect(store.items.isEmpty)
        #expect(defaults.object(forKey: "infuraAPIKey") == nil)
        #expect(defaults.object(forKey: "rpcURL") == nil)
    }

    @Test func failedWriteKeepsUserDefaultsCopy() {
        defaults.set(key, forKey: "infuraAPIKey")
        let store = InMemorySecretStore()
        store.failWrites = true

        #expect(AppSettings.loadInfuraAPIKey(defaults: defaults, secrets: store) == key)
        #expect(defaults.string(forKey: "infuraAPIKey") == key)

        // The next launch retries and finishes the move.
        store.failWrites = false
        #expect(AppSettings.loadInfuraAPIKey(defaults: defaults, secrets: store) == key)
        #expect(store.items[account] == key)
        #expect(defaults.object(forKey: "infuraAPIKey") == nil)
    }

    @Test func freshInstallReadsOnlyFromStore() {
        #expect(AppSettings.loadInfuraAPIKey(defaults: defaults, secrets: InMemorySecretStore()) == "")
        #expect(AppSettings.loadInfuraAPIKey(defaults: defaults, secrets: InMemorySecretStore([account: key])) == key)
    }
}

@Suite struct KeychainStoreTests {
    @Test func setReadUpdateAndDeleteRoundTrip() {
        let store = KeychainStore(service: "PoolserTests.\(UUID().uuidString)")
        defer { store.set("", forAccount: account) }

        #expect(store.string(forAccount: account) == nil)
        #expect(store.set(key, forAccount: account))
        #expect(store.string(forAccount: account) == key)
        #expect(store.set("replaced", forAccount: account))
        #expect(store.string(forAccount: account) == "replaced")
        #expect(store.set("", forAccount: account))
        #expect(store.string(forAccount: account) == nil)
        // Deleting an item that is already gone is not an error.
        #expect(store.set("", forAccount: account))
    }
}
