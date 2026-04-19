import Foundation
import Combine
import ServiceManagement

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Defaults {
        static let refreshIntervalMinutes = 10
        static let enabledChainIDs = ["ethereum"]
        static let rpcCreditsPerSecondBudget = 400
        static let v4LogChunkSize = 20_000
        static let v4LogMaxConcurrentRequests = 3
        static let v4BootstrapMaxChunksPerRefresh = 120
    }

    @Published var walletAddress: String {
        didSet {
            UserDefaults.standard.set(walletAddress, forKey: "walletAddress")
            if walletAddress != oldValue { Task { @MainActor in LogStore.shared.clear() } }
        }
    }
    @Published var infuraAPIKey: String {
        didSet { UserDefaults.standard.set(infuraAPIKey, forKey: "infuraAPIKey") }
    }
    @Published var enabledChainIDs: Set<String> {
        didSet {
            let persisted = Array(enabledChainIDs).sorted().joined(separator: ",")
            UserDefaults.standard.set(persisted, forKey: "enabledChainIDs")
        }
    }
    @Published var refreshIntervalMinutes: Int {
        didSet {
            let clamped = Self.clamp(refreshIntervalMinutes, min: 1, max: 120)
            if clamped != refreshIntervalMinutes {
                refreshIntervalMinutes = clamped
                return
            }
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
        }
    }
    @Published var rpcCreditsPerSecondBudget: Int {
        didSet {
            let clamped = Self.clamp(rpcCreditsPerSecondBudget, min: 50, max: 5_000)
            if clamped != rpcCreditsPerSecondBudget {
                rpcCreditsPerSecondBudget = clamped
                return
            }
            UserDefaults.standard.set(rpcCreditsPerSecondBudget, forKey: "rpcCreditsPerSecondBudget")
        }
    }
    @Published var v4LogChunkSize: Int {
        didSet {
            let clamped = Self.clamp(v4LogChunkSize, min: 1_000, max: 50_000)
            if clamped != v4LogChunkSize {
                v4LogChunkSize = clamped
                return
            }
            UserDefaults.standard.set(v4LogChunkSize, forKey: "v4LogChunkSize")
        }
    }
    @Published var v4LogMaxConcurrentRequests: Int {
        didSet {
            let clamped = Self.clamp(v4LogMaxConcurrentRequests, min: 1, max: 8)
            if clamped != v4LogMaxConcurrentRequests {
                v4LogMaxConcurrentRequests = clamped
                return
            }
            UserDefaults.standard.set(v4LogMaxConcurrentRequests, forKey: "v4LogMaxConcurrentRequests")
        }
    }
    @Published var v4BootstrapMaxChunksPerRefresh: Int {
        didSet {
            let clamped = Self.clamp(v4BootstrapMaxChunksPerRefresh, min: 5, max: 200)
            if clamped != v4BootstrapMaxChunksPerRefresh {
                v4BootstrapMaxChunksPerRefresh = clamped
                return
            }
            UserDefaults.standard.set(v4BootstrapMaxChunksPerRefresh, forKey: "v4BootstrapMaxChunksPerRefresh")
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    @Published var flashOnValueChange: Bool {
        didSet { UserDefaults.standard.set(flashOnValueChange, forKey: "flashOnValueChange") }
    }
    @Published var loginItemError: String?

    private init() {
        let ud = UserDefaults.standard
        walletAddress = ud.string(forKey: "walletAddress") ?? ""
        let savedInfuraKey = ud.string(forKey: "infuraAPIKey") ?? ""
        let migratedInfuraKey: String
        if savedInfuraKey.isEmpty, let oldRPC = ud.string(forKey: "rpcURL") {
            migratedInfuraKey = Self.extractInfuraKey(from: oldRPC) ?? ""
        } else {
            migratedInfuraKey = savedInfuraKey
        }
        infuraAPIKey = migratedInfuraKey
        let enabledRaw = ud.string(forKey: "enabledChainIDs") ?? Defaults.enabledChainIDs.joined(separator: ",")
        let enabled = Set(enabledRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .intersection(Set(SupportedChain.all.map(\.id)))
        enabledChainIDs = enabled.isEmpty ? Set(Defaults.enabledChainIDs) : enabled
        let refreshRaw = ud.object(forKey: "refreshIntervalMinutes") as? Int ?? Defaults.refreshIntervalMinutes
        refreshIntervalMinutes = Self.clamp(refreshRaw, min: 1, max: 120)
        let cpsRaw = ud.object(forKey: "rpcCreditsPerSecondBudget") as? Int ?? Defaults.rpcCreditsPerSecondBudget
        rpcCreditsPerSecondBudget = Self.clamp(cpsRaw, min: 50, max: 5_000)
        let chunkRaw = ud.object(forKey: "v4LogChunkSize") as? Int ?? Defaults.v4LogChunkSize
        v4LogChunkSize = Self.clamp(chunkRaw, min: 1_000, max: 50_000)
        let concurrentRaw = ud.object(forKey: "v4LogMaxConcurrentRequests") as? Int ?? Defaults.v4LogMaxConcurrentRequests
        v4LogMaxConcurrentRequests = Self.clamp(concurrentRaw, min: 1, max: 8)
        let bootstrapRaw = ud.object(forKey: "v4BootstrapMaxChunksPerRefresh") as? Int ?? Defaults.v4BootstrapMaxChunksPerRefresh
        v4BootstrapMaxChunksPerRefresh = Self.clamp(bootstrapRaw, min: 5, max: 200)

        flashOnValueChange = ud.object(forKey: "flashOnValueChange") as? Bool ?? true

        // Sync stored preference with the actual service status on launch
        let actuallyEnabled = SMAppService.mainApp.status == .enabled
        launchAtLogin = actuallyEnabled
        ud.set(actuallyEnabled, forKey: "launchAtLogin")
    }

    @MainActor
    func setLaunchAtLogin(_ enabled: Bool) async {
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

    func resetPerformanceDefaults() {
        refreshIntervalMinutes = Defaults.refreshIntervalMinutes
        rpcCreditsPerSecondBudget = Defaults.rpcCreditsPerSecondBudget
        v4LogChunkSize = Defaults.v4LogChunkSize
        v4LogMaxConcurrentRequests = Defaults.v4LogMaxConcurrentRequests
        v4BootstrapMaxChunksPerRefresh = Defaults.v4BootstrapMaxChunksPerRefresh
    }

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

    func infuraRPCURL(for chain: SupportedChain) -> URL? {
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

    private static func extractInfuraKey(from rpcURL: String) -> String? {
        guard let url = URL(string: rpcURL),
              url.host?.contains("infura.io") == true else { return nil }
        let parts = url.pathComponents
        guard let idx = parts.firstIndex(of: "v3"), idx + 1 < parts.count else { return nil }
        let key = parts[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }
}
