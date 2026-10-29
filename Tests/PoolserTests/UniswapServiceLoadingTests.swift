import Foundation
import Testing
@testable import PoolserKit

@MainActor
@Suite(.serialized)
struct UniswapServiceLoadingTests {
    /// Polls the main actor until `condition` holds or the timeout elapses.
    private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func invalidConfigClearsLoadingLeftByEarlierLoad() async throws {
        // An empty Infura key makes load() take the config-error exit without any network calls.
        let savedKey = AppSettings.shared.infuraAPIKey
        AppSettings.shared.infuraAPIKey = ""
        defer { AppSettings.shared.infuraAPIKey = savedKey }

        let service = UniswapService()
        try await waitUntil { service.lastError != nil }
        #expect(service.lastError != nil)

        // Simulate a refresh still in flight when the config became invalid.
        service.isLoading = true
        service.lastError = nil
        service.refresh()

        try await waitUntil { service.lastError != nil }
        #expect(service.lastError != nil)
        #expect(service.isLoading == false)
    }
}
