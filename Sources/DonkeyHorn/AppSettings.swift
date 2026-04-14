import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Defaults {
        static let refreshIntervalMinutes = 10
        static let rpcCreditsPerSecondBudget = 400
        static let v4LogChunkSize = 12_000
        static let v4LogMaxConcurrentRequests = 2
        static let v4BootstrapMaxChunksPerRefresh = 80
    }

    @Published var walletAddress: String {
        didSet {
            UserDefaults.standard.set(walletAddress, forKey: "walletAddress")
            if walletAddress != oldValue { Task { @MainActor in LogStore.shared.clear() } }
        }
    }
    @Published var rpcURL: String {
        didSet { UserDefaults.standard.set(rpcURL, forKey: "rpcURL") }
    }
    @Published var refreshIntervalMinutes: Int {
        didSet {
            refreshIntervalMinutes = Self.clamp(refreshIntervalMinutes, min: 1, max: 120)
            UserDefaults.standard.set(refreshIntervalMinutes, forKey: "refreshIntervalMinutes")
        }
    }
    @Published var rpcCreditsPerSecondBudget: Int {
        didSet {
            rpcCreditsPerSecondBudget = Self.clamp(rpcCreditsPerSecondBudget, min: 50, max: 5_000)
            UserDefaults.standard.set(rpcCreditsPerSecondBudget, forKey: "rpcCreditsPerSecondBudget")
        }
    }
    @Published var v4LogChunkSize: Int {
        didSet {
            v4LogChunkSize = Self.clamp(v4LogChunkSize, min: 1_000, max: 50_000)
            UserDefaults.standard.set(v4LogChunkSize, forKey: "v4LogChunkSize")
        }
    }
    @Published var v4LogMaxConcurrentRequests: Int {
        didSet {
            v4LogMaxConcurrentRequests = Self.clamp(v4LogMaxConcurrentRequests, min: 1, max: 8)
            UserDefaults.standard.set(v4LogMaxConcurrentRequests, forKey: "v4LogMaxConcurrentRequests")
        }
    }
    @Published var v4BootstrapMaxChunksPerRefresh: Int {
        didSet {
            v4BootstrapMaxChunksPerRefresh = Self.clamp(v4BootstrapMaxChunksPerRefresh, min: 5, max: 200)
            UserDefaults.standard.set(v4BootstrapMaxChunksPerRefresh, forKey: "v4BootstrapMaxChunksPerRefresh")
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    @Published var loginItemError: String?

    private init() {
        let ud = UserDefaults.standard
        walletAddress = ud.string(forKey: "walletAddress") ?? ""
        rpcURL = ud.string(forKey: "rpcURL") ?? ""
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

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(value, max))
    }
}
