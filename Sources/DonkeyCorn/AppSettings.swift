import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var walletAddress: String {
        didSet { UserDefaults.standard.set(walletAddress, forKey: "walletAddress") }
    }
    @Published var rpcURL: String {
        didSet { UserDefaults.standard.set(rpcURL, forKey: "rpcURL") }
    }
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin") }
    }
    @Published var loginItemError: String?

    private init() {
        let ud = UserDefaults.standard
        walletAddress = ud.string(forKey: "walletAddress") ?? ""
        rpcURL = ud.string(forKey: "rpcURL") ?? ""

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
}
