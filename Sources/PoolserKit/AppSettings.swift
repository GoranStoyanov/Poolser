import Foundation
import Combine
#if os(macOS)
import ServiceManagement
#endif

public struct HiddenPosition: Codable, Equatable, Identifiable {
    public let id: String
    public let label: String

    public init(_ position: Position) {
        id = position.id
        label = "\(position.sym0)/\(position.sym1) · \(position.chainName) \(position.versionLabel) · #\(position.tokenId)"
    }
}

enum HiddenPositionStore {
    static func visible(_ positions: [Position], hidden: [HiddenPosition]) -> [Position] {
        let ids = Set(hidden.map(\.id))
        return positions.filter { !ids.contains($0.id) }
    }

    static func key(for wallet: String) -> String {
        "hiddenPositions.\(wallet.lowercased())"
    }

    static func load(wallet: String, from defaults: UserDefaults) -> [HiddenPosition] {
        guard let data = defaults.data(forKey: key(for: wallet)) else { return [] }
        return (try? JSONDecoder().decode([HiddenPosition].self, from: data)) ?? []
    }

    static func save(_ positions: [HiddenPosition], wallet: String, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(positions) else { return }
        defaults.set(data, forKey: key(for: wallet))
    }
}

/// Main-actor isolated: SwiftUI writes these values on the main thread. Network code must not
/// read them directly; callers snapshot what a load needs and pass the values down.
@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    public enum Defaults {
        public static let refreshIntervalMinutes = 10
        static let enabledChainIDs = ["ethereum"]
        public static let rpcCreditsPerSecondBudget = 400
        public static let v4LogChunkSize = 10_000
        public static let v4LogMaxConcurrentRequests = 3
        public static let v4BootstrapMaxChunksPerRefresh = 120
        /// Infura rejects eth_getLogs spanning more than 10,000 blocks
        /// ("range 11999 exceeds limit of 10000"), so larger chunks can never succeed.
        public static let v4LogChunkSizeRange = 1_000...10_000
    }

    nonisolated static func clampLogChunkSize(_ value: Int) -> Int {
        Swift.max(Defaults.v4LogChunkSizeRange.lowerBound, Swift.min(value, Defaults.v4LogChunkSizeRange.upperBound))
    }

    @Published public private(set) var walletAddresses: [String] {
        didSet { PoolserDefaults.store.set(walletAddresses, forKey: "walletAddresses") }
    }
    @Published public var walletAddress: String {
        didSet {
            PoolserDefaults.store.set(walletAddress, forKey: "walletAddress")
            if walletAddress != oldValue {
                if let wallet = WalletAddress.normalize(walletAddress),
                   !walletAddresses.contains(where: { $0.caseInsensitiveCompare(wallet) == .orderedSame }) {
                    walletAddresses.append(wallet)
                }
                hiddenPositions = HiddenPositionStore.load(wallet: walletAddress, from: PoolserDefaults.store)
                Task { @MainActor in LogStore.shared.clear() }
            }
        }
    }
    /// Persisted in the Keychain. Read once at launch and kept here, so request paths never
    /// touch the Keychain.
    @Published public var infuraAPIKey: String {
        didSet {
            guard infuraAPIKey != oldValue else { return }
            if !secrets.set(infuraAPIKey, forAccount: Self.infuraKeyAccount) {
                LogStore.shared.log("Could not save the Infura API key to the Keychain", level: .error)
            }
        }
    }
    @Published public var enabledChainIDs: Set<String> {
        didSet {
            let persisted = Array(enabledChainIDs).sorted().joined(separator: ",")
            PoolserDefaults.store.set(persisted, forKey: "enabledChainIDs")
        }
    }
    @Published public var refreshIntervalMinutes: Int {
        didSet {
            let clamped = Self.clamp(refreshIntervalMinutes, min: 1, max: 120)
            if clamped != refreshIntervalMinutes {
                refreshIntervalMinutes = clamped
                return
            }
            PoolserDefaults.store.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
        }
    }
    @Published public var rpcCreditsPerSecondBudget: Int {
        didSet {
            let clamped = Self.clamp(rpcCreditsPerSecondBudget, min: 50, max: 5_000)
            if clamped != rpcCreditsPerSecondBudget {
                rpcCreditsPerSecondBudget = clamped
                return
            }
            PoolserDefaults.store.set(rpcCreditsPerSecondBudget, forKey: "rpcCreditsPerSecondBudget")
        }
    }
    @Published public var v4LogChunkSize: Int {
        didSet {
            let clamped = Self.clampLogChunkSize(v4LogChunkSize)
            if clamped != v4LogChunkSize {
                v4LogChunkSize = clamped
                return
            }
            PoolserDefaults.store.set(v4LogChunkSize, forKey: "v4LogChunkSize")
        }
    }
    @Published public var v4LogMaxConcurrentRequests: Int {
        didSet {
            let clamped = Self.clamp(v4LogMaxConcurrentRequests, min: 1, max: 8)
            if clamped != v4LogMaxConcurrentRequests {
                v4LogMaxConcurrentRequests = clamped
                return
            }
            PoolserDefaults.store.set(v4LogMaxConcurrentRequests, forKey: "v4LogMaxConcurrentRequests")
        }
    }
    @Published public var v4BootstrapMaxChunksPerRefresh: Int {
        didSet {
            let clamped = Self.clamp(v4BootstrapMaxChunksPerRefresh, min: 5, max: 200)
            if clamped != v4BootstrapMaxChunksPerRefresh {
                v4BootstrapMaxChunksPerRefresh = clamped
                return
            }
            PoolserDefaults.store.set(v4BootstrapMaxChunksPerRefresh, forKey: "v4BootstrapMaxChunksPerRefresh")
        }
    }
    @Published public var launchAtLogin: Bool {
        didSet { PoolserDefaults.store.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    @Published public var flashOnValueChange: Bool {
        didSet { PoolserDefaults.store.set(flashOnValueChange, forKey: "flashOnValueChange") }
    }
    @Published public var trackClaimedFees: Bool {
        didSet { PoolserDefaults.store.set(trackClaimedFees, forKey: "trackClaimedFees") }
    }
    @Published public var notifyOnRangeChange: Bool {
        didSet { PoolserDefaults.store.set(notifyOnRangeChange, forKey: "notifyOnRangeChange") }
    }
    @Published public var positionListOptions: PositionListOptions {
        didSet {
            guard positionListOptions != oldValue else { return }
            positionListOptions.save(to: PoolserDefaults.store)
        }
    }
    @Published public private(set) var hiddenPositions: [HiddenPosition] {
        didSet {
            HiddenPositionStore.save(hiddenPositions, wallet: walletAddress, to: PoolserDefaults.store)
        }
    }
    @Published public var loginItemError: String?

    nonisolated static let infuraKeyAccount = "infuraAPIKey"
    private let secrets: SecretStore

    private init(secrets: SecretStore = KeychainStore()) {
        self.secrets = secrets
        let ud = PoolserDefaults.store
        // Older builds saved the field verbatim, so a pasted newline or space could be stored.
        let storedWallet = ud.string(forKey: "walletAddress") ?? ""
        let wallet = WalletAddress.normalize(storedWallet)
            ?? storedWallet.trimmingCharacters(in: .whitespacesAndNewlines)
        if wallet != storedWallet { ud.set(wallet, forKey: "walletAddress") }
        let storedWallets = ud.stringArray(forKey: "walletAddresses") ?? []
        let wallets = WalletAddress.unique([wallet] + storedWallets)
        if wallets != storedWallets { ud.set(wallets, forKey: "walletAddresses") }
        let activeWallet = wallets.first(where: { $0.caseInsensitiveCompare(wallet) == .orderedSame })
            ?? wallets.first ?? wallet
        if activeWallet != wallet { ud.set(activeWallet, forKey: "walletAddress") }
        walletAddresses = wallets
        walletAddress = activeWallet
        hiddenPositions = HiddenPositionStore.load(wallet: activeWallet, from: ud)
        infuraAPIKey = Self.loadInfuraAPIKey(defaults: ud, secrets: secrets)
        let enabledRaw = ud.string(forKey: "enabledChainIDs") ?? Defaults.enabledChainIDs.joined(separator: ",")
        let enabled = Set(enabledRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .intersection(Set(SupportedChain.all.map(\.id)))
        enabledChainIDs = enabled.isEmpty ? Set(Defaults.enabledChainIDs) : enabled
        let refreshRaw = ud.object(forKey: "refreshIntervalMinutes") as? Int ?? Defaults.refreshIntervalMinutes
        refreshIntervalMinutes = Self.clamp(refreshRaw, min: 1, max: 120)
        let cpsRaw = ud.object(forKey: "rpcCreditsPerSecondBudget") as? Int ?? Defaults.rpcCreditsPerSecondBudget
        rpcCreditsPerSecondBudget = Self.clamp(cpsRaw, min: 50, max: 5_000)
        let chunkRaw = ud.object(forKey: "v4LogChunkSize") as? Int ?? Defaults.v4LogChunkSize
        v4LogChunkSize = Self.clampLogChunkSize(chunkRaw)
        let concurrentRaw = ud.object(forKey: "v4LogMaxConcurrentRequests") as? Int ?? Defaults.v4LogMaxConcurrentRequests
        v4LogMaxConcurrentRequests = Self.clamp(concurrentRaw, min: 1, max: 8)
        let bootstrapRaw = ud.object(forKey: "v4BootstrapMaxChunksPerRefresh") as? Int ?? Defaults.v4BootstrapMaxChunksPerRefresh
        v4BootstrapMaxChunksPerRefresh = Self.clamp(bootstrapRaw, min: 5, max: 200)

        flashOnValueChange = ud.object(forKey: "flashOnValueChange") as? Bool ?? true
        trackClaimedFees = ud.object(forKey: "trackClaimedFees") as? Bool ?? false
        notifyOnRangeChange = ud.object(forKey: "notifyOnRangeChange") as? Bool ?? false
        positionListOptions = PositionListOptions(defaults: ud)

        #if os(macOS)
        // Sync stored preference with the actual service status on launch
        let actuallyEnabled = SMAppService.mainApp.status == .enabled
        #else
        let actuallyEnabled = false
        #endif
        launchAtLogin = actuallyEnabled
        ud.set(actuallyEnabled, forKey: "launchAtLogin")
    }

    #if os(macOS)
    public func setLaunchAtLogin(_ enabled: Bool) async {
        loginItemError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            loginItemError = error.localizedDescription
            launchAtLogin = !enabled  // revert toggle to reflect actual state
        }
    }
    #endif

    func isChainEnabled(_ chainID: String) -> Bool {
        enabledChainIDs.contains(chainID)
    }

    func setChainEnabled(_ chainID: String, enabled: Bool) {
        if enabled { enabledChainIDs.insert(chainID) }
        else { enabledChainIDs.remove(chainID) }
    }

    func enabledChains() -> [SupportedChain] {
        SupportedChain.all.filter { enabledChainIDs.contains($0.id) }
    }

    public func setWalletAddresses(_ addresses: [String], active: String) {
        let wallets = WalletAddress.unique(addresses)
        walletAddresses = wallets
        walletAddress = wallets.first(where: { $0.caseInsensitiveCompare(active) == .orderedSame }) ?? wallets.first ?? ""
    }

    public func hide(_ position: Position) {
        guard !hiddenPositions.contains(where: { $0.id == position.id }) else { return }
        hiddenPositions.append(HiddenPosition(position))
    }

    public func showPosition(id: String) {
        hiddenPositions.removeAll { $0.id == id }
    }

    public func infuraRPCURL(for chain: SupportedChain) -> URL? {
        let key = infuraAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return URL(string: "https://\(chain.infuraHost).infura.io/v3/\(key)")
    }

    func disableChain(_ chainID: String) {
        enabledChainIDs.remove(chainID)
    }

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(value, max))
    }

    /// Returns the stored Infura key, moving one left in UserDefaults by older builds
    /// (`infuraAPIKey`, or the key inside a legacy `rpcURL`) into `secrets`. The UserDefaults
    /// copies are removed only once the key is safely in `secrets`, so a failed write loses nothing.
    nonisolated static func loadInfuraAPIKey(defaults: UserDefaults, secrets: SecretStore) -> String {
        let legacyKeys = ["infuraAPIKey", "rpcURL"]
        var key = secrets.string(forAccount: infuraKeyAccount) ?? ""
        guard legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return key }

        if key.isEmpty {
            key = defaults.string(forKey: "infuraAPIKey") ?? ""
            if key.isEmpty, let oldRPC = defaults.string(forKey: "rpcURL") {
                key = extractInfuraKey(from: oldRPC) ?? ""
            }
            if !key.isEmpty, !secrets.set(key, forAccount: infuraKeyAccount) { return key }
        }
        legacyKeys.forEach(defaults.removeObject(forKey:))
        return key
    }

    private nonisolated static func extractInfuraKey(from rpcURL: String) -> String? {
        guard let url = URL(string: rpcURL),
              url.host?.contains("infura.io") == true else { return nil }
        let parts = url.pathComponents
        guard let idx = parts.firstIndex(of: "v3"), idx + 1 < parts.count else { return nil }
        let key = parts[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}

public enum WalletAddress {
    static func unique(_ addresses: [String]) -> [String] {
        var seen = Set<String>()
        return addresses.compactMap(normalize).filter { seen.insert($0.lowercased()).inserted }
    }

    /// Returns the address as `0x` + 40 hex digits, without surrounding whitespace, or nil if
    /// the input is not an address. `ABI.encodeAddress` turns anything else into the zero address.
    public static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") ? trimmed.dropFirst(2) : Substring(trimmed)
        // isHexDigit alone also accepts fullwidth digits and letters.
        guard hex.count == 40, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return "0x" + hex
    }

    /// Message for the Settings field, or nil when the input can be saved (an empty field is allowed).
    public static func validationError(for raw: String) -> String? {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        return normalize(raw) == nil ? "Enter a valid address: 0x followed by 40 hex characters." : nil
    }
}
