import Testing
@testable import PoolserKit

private func makePosition(fees: Double?, claimed: Double?, syncing: Bool = false, error: String? = nil) -> Position {
    var p = Position(
        chainID: "ethereum", chainName: "Ethereum", chainNumericID: 1,
        tokenId: "1", token0: "", token1: "",
        sym0: "A", sym1: "B", feePct: "0.05", feeRaw: 500,
        fees0: 0, fees1: 0, tickLower: -100, tickUpper: 100,
        liquidity: 1,
        error: error
    )
    p.usd = fees
    p.claimedUSD = claimed
    p.feeHistoryBootstrapping = syncing
    return p
}

@Suite("Wallet fee summary")
struct WalletFeeSummaryTests {
    @Test func addsClaimedAndUnclaimedAcrossPositions() {
        let summary = WalletFeeSummary(positions: [
            makePosition(fees: 200, claimed: 1_000),
            makePosition(fees: 50.5, claimed: nil),   // v4, or no Collect yet
            makePosition(fees: nil, claimed: 30),     // fees not priced
        ])
        #expect(summary.unclaimedUSD == 250.5)
        #expect(summary.claimedUSD == 1_030)
        #expect(summary.allTimeUSD == 1_280.5)
        #expect(!summary.isSyncing)
    }

    @Test func positionsThatFailedToLoadAreLeftOut() {
        let summary = WalletFeeSummary(positions: [
            makePosition(fees: 10, claimed: 5),
            makePosition(fees: 999, claimed: 999, error: "read failed"),
        ])
        #expect(summary.allTimeUSD == 15)
    }

    @Test func anyBootstrappingPositionMarksTheTotalAsSyncing() {
        let summary = WalletFeeSummary(positions: [
            makePosition(fees: 10, claimed: 5),
            makePosition(fees: 1, claimed: nil, syncing: true),
        ])
        #expect(summary.isSyncing)
    }

    @Test func emptyWalletIsZero() {
        #expect(WalletFeeSummary(positions: []).allTimeUSD == 0)
    }
}
