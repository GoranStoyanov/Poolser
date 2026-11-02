import Foundation
import Testing
@testable import PoolserKit

@MainActor
@Suite(.serialized)
struct UniswapServiceLoadingTests {
    private let ethereum = SupportedChain.byID("ethereum")!
    private let base = SupportedChain.byID("base")!

    private func position(_ tokenID: String, chain: SupportedChain, isV4: Bool = false) -> Position {
        Position(
            chainID: chain.id, chainName: chain.displayName, chainNumericID: chain.chainId,
            tokenId: tokenID, token0: "", token1: "", sym0: "A", sym1: "B",
            feePct: "0.05", feeRaw: 500, fees0: 1, fees1: 0,
            tickLower: -100, tickUpper: 100, liquidity: 1, inRange: true, isV4: isV4
        )
    }

    private func result(
        _ chain: SupportedChain, positions: [Position] = [], error: String? = nil,
        failedV3: Bool = false, failedV4: Bool = false
    ) -> ChainLoadResult {
        ChainLoadResult(
            chain: chain, positions: positions, feesUSD: 0, error: error,
            bootstrapInProgress: false, bootstrapNextFromBlock: nil,
            failedV3: failedV3, failedV4: failedV4
        )
    }

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

    @Test func offlineRefreshKeepsLastPositionsAndUpdateTimeWithoutRecordingStaleFees() {
        var portfolio = WalletPortfolio()
        let earlier = Date(timeIntervalSince1970: 1_800_000_000)
        let ethPosition = position("1", chain: ethereum)
        let basePosition = position("2", chain: base)
        let active = [ethereum, base]

        #expect(portfolio.apply([
            result(ethereum, positions: [ethPosition]), result(base, positions: [basePosition])
        ], activeChains: active, at: earlier).map(\.id) == [ethPosition.id, basePosition.id])
        #expect(portfolio.lastUpdated == earlier)

        _ = portfolio.apply([result(base, positions: [basePosition])],
                            activeChains: active, at: earlier.addingTimeInterval(30))
        #expect(portfolio.lastUpdated == earlier)

        let offline = earlier.addingTimeInterval(60)
        #expect(portfolio.apply([
            result(ethereum, error: "Ethereum: RPC unavailable", failedV3: true, failedV4: true),
            result(base, error: "Base: RPC unavailable", failedV3: true, failedV4: true)
        ], activeChains: active, at: offline).isEmpty)
        #expect(Set(portfolio.allPositions.map(\.id)) == Set([ethPosition.id, basePosition.id]))
        #expect(portfolio.lastUpdated == earlier)
        #expect(portfolio.chainResultsByID[ethereum.id]?.error == "Ethereum: RPC unavailable")
        #expect(portfolio.chainResultsByID[base.id]?.error == "Base: RPC unavailable")

        let partial = offline.addingTimeInterval(60)
        let freshBase = position("3", chain: base)
        #expect(portfolio.apply([
            result(ethereum, error: "Ethereum: RPC unavailable", failedV3: true, failedV4: true),
            result(base, positions: [freshBase])
        ], activeChains: active, at: partial).map(\.id) == [freshBase.id])
        #expect(Set(portfolio.allPositions.map(\.id)) == Set([ethPosition.id, freshBase.id]))
        #expect(portfolio.lastUpdated == earlier)

        let restored = partial.addingTimeInterval(60)
        #expect(portfolio.apply([
            result(ethereum, positions: []), result(base, positions: [freshBase])
        ], activeChains: active, at: restored).map(\.id) == [freshBase.id])
        #expect(portfolio.allPositions.map(\.id) == [freshBase.id])
        #expect(portfolio.chainResultsByID[ethereum.id]?.error == nil)
        #expect(portfolio.lastUpdated == restored)
    }

    @Test func cachedPortfolioSurvivesOfflineRestartAndRespectsEnabledChains() throws {
        let suite = "PoolserTests.portfolio.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let wallet = "0x1111111111111111111111111111111111111111"
        let updated = Date(timeIntervalSince1970: 1_800_000_000)
        var eth = position("1", chain: ethereum)
        eth.positionUSD = 123
        eth.poolAddress = "0xpool"
        let basePosition = position("2", chain: base)
        WalletPortfolioCache(positions: [eth, basePosition], updatedAt: updated).save(wallet: wallet, to: defaults)

        let cached = try #require(WalletPortfolioCache.load(wallet: wallet.uppercased(), from: defaults))
        var restored = cached.portfolio(activeChains: [ethereum])
        #expect(restored.allPositions.map(\.id) == [eth.id])
        #expect(restored.allPositions[0].positionUSD == 123)
        #expect(restored.allPositions[0].poolAddress == "0xpool")
        #expect(restored.lastUpdated == updated)

        let fresh = restored.apply([
            result(ethereum, error: "Ethereum: RPC unavailable", failedV3: true, failedV4: true)
        ], activeChains: [ethereum], at: updated.addingTimeInterval(60))
        #expect(fresh.isEmpty)
        #expect(restored.allPositions.map(\.id) == [eth.id])
        #expect(restored.lastUpdated == updated)

        WalletPortfolioCache.remove(wallet: wallet, from: defaults)
        #expect(WalletPortfolioCache.load(wallet: wallet, from: defaults) == nil)
    }

    #if os(macOS)
    @Test func networkRecoveryRefreshesOnlyAfterAnActualOutage() {
        var recovery = NetworkRecovery()
        let refreshes = [true, true, false, false, true, true].map {
            recovery.update(available: $0)
        }
        #expect(refreshes == [false, false, false, false, true, false])
    }
    #endif

    @Test func coldOfflineLoadAndDisabledChainDoNotShowInventedPositions() {
        var portfolio = WalletPortfolio()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(portfolio.apply([
            result(ethereum, error: "Ethereum: RPC unavailable", failedV3: true, failedV4: true)
        ], activeChains: [ethereum], at: now).isEmpty)
        #expect(portfolio.allPositions.isEmpty)
        #expect(portfolio.lastUpdated == nil)

        _ = portfolio.apply([result(ethereum, positions: [position("1", chain: ethereum)])],
                            activeChains: [ethereum], at: now)
        _ = portfolio.apply([result(base, positions: [])], activeChains: [base], at: now.addingTimeInterval(60))
        #expect(portfolio.allPositions.isEmpty)
        #expect(portfolio.chainResultsByID[ethereum.id] == nil)
    }

    @Test func oneProtocolFailureKeepsOnlyItsPreviousPositions() {
        var portfolio = WalletPortfolio()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldV3 = position("1", chain: ethereum)
        let oldV4 = position("2", chain: ethereum, isV4: true)
        _ = portfolio.apply([result(ethereum, positions: [oldV3, oldV4])], activeChains: [ethereum], at: now)

        let newV4 = position("3", chain: ethereum, isV4: true)
        let fresh = portfolio.apply([
            result(ethereum, positions: [newV4], error: "v3 failed", failedV3: true)
        ], activeChains: [ethereum], at: now.addingTimeInterval(60))
        #expect(fresh.map(\.id) == [newV4.id])
        #expect(Set(portfolio.allPositions.map(\.id)) == Set([oldV3.id, newV4.id]))
        #expect(portfolio.lastUpdated == now)

        let newV3 = position("4", chain: ethereum)
        _ = portfolio.apply([
            result(ethereum, positions: [newV3], error: "v4 failed", failedV4: true)
        ], activeChains: [ethereum], at: now.addingTimeInterval(120))
        #expect(Set(portfolio.allPositions.map(\.id)) == Set([newV3.id, newV4.id]))

        _ = portfolio.apply([result(ethereum, positions: [newV3])],
                            activeChains: [ethereum], at: now.addingTimeInterval(180))
        #expect(portfolio.allPositions.map(\.id) == [newV3.id])
    }

    @Test func offlineProbeDoesNotDisableNetwork() async {
        let eth = EthereumClient(
            rpcURL: URL(string: "https://rpc.test")!,
            limiter: RPCCreditLimiter(creditsPerSecond: 1_000, maxBurstCredits: 1_000)
        ) { _ in throw URLError(.notConnectedToInternet) }
        let failure = await ChainPrefetch.probe(chain: ethereum, eth: eth)
        #expect(failure?.accessDenied == false)
        #expect(failure?.error?.contains("RPC unavailable") == true)
    }

    @Test func identicalChainFailuresAreShownOnce() {
        let offline = "RPC unavailable – The Internet connection appears to be offline."
        let failures = [
            result(ethereum, error: "Ethereum: \(offline)"),
            result(base, error: "Base: \(offline)")
        ]
        #expect(ChainLoadResult.sharedFailure(failures) == "\(offline) (all 2 networks)")
        #expect(ChainLoadResult.sharedFailure([
            failures[0], result(base, error: "Base: rate limited")
        ]) == nil)
        #expect(ChainLoadResult.sharedFailure([
            failures[0], result(base)
        ]) == nil)
    }
}
