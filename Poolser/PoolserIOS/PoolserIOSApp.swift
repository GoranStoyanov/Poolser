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
            IOSPortfolioView()
                .environmentObject(service)
        }
    }
}
