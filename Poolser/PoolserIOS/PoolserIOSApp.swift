import SwiftUI
import PoolserKit

@main
struct PoolserIOSApp: App {
    @StateObject private var service: UniswapService

    init() {
        let service = UniswapService()
        _service = StateObject(wrappedValue: service)
        IOSBackgroundRefresh.register(service: service)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["POOLSER_SCREENSHOT_DEMO"] == "1" {
                IOSReleasePreview()
            } else {
                IOSPortfolioView()
                    .environmentObject(service)
            }
            #else
            IOSPortfolioView()
                .environmentObject(service)
            #endif
        }
    }
}
