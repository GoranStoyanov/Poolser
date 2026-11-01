import CoreGraphics
import Foundation
import Testing
@testable import PoolserKit

private func makePosition(
    _ tokenId: String,
    chainID: String = "ethereum",
    inRange: Bool? = true,
    value: Double? = nil,
    fees: Double? = nil,
    claimed: Double? = nil
) -> Position {
    var p = Position(
        chainID: chainID, chainName: chainID.capitalized, chainNumericID: 1,
        tokenId: tokenId, token0: "", token1: "",
        sym0: "WETH", sym1: "USDC", feePct: "0.05", feeRaw: 500,
        fees0: 0, fees1: 0, tickLower: -100, tickUpper: 100,
        liquidity: 1,
        inRange: inRange
    )
    p.positionUSD = value
    p.usd = fees
    p.claimedUSD = claimed
    return p
}

private let trezor = SavedWallet(address: "0x51c0aa29d4e7b3f8e2a9b6c1d0e4f7a3b8c2d9e1", name: "Trezor")
private let main = SavedWallet(address: "0x7a3f9c2e81b54d06a1f3e8b2c97d40e5f1a6c41e", name: "Main")
private let hot = SavedWallet(address: "0x3e19aa29d4e7b3f8e2a9b6c1d0e4f7a3b8c2a0b4")

@Suite("Wallet overview")
struct WalletOverviewTests {
    @Test func totalsAndSharesCoverEveryWallet() {
        let overview = WalletOverview(
            wallets: [
                (main, [makePosition("1", value: 250, fees: 5), makePosition("2", chainID: "base", value: 50, fees: 1)]),
                (trezor, [makePosition("3", value: 700, fees: 4)]),
            ],
            tracksClaimedFees: false
        )
        #expect(overview.totalValueUSD == 1_000)
        #expect(overview.unclaimedFeesUSD == 10)
        #expect(overview.positionCount == 3)
        #expect(overview.chainCount == 2)
        #expect(overview.entries.map(\.share) == [0.7, 0.3])
        #expect(overview.entries.map(\.unclaimedFeesUSD) == [4, 6])
    }

    @Test func largestWalletFirstButColoursFollowTheSavedList() {
        let overview = WalletOverview(
            wallets: [
                (main, [makePosition("1", value: 100)]),
                (trezor, [makePosition("2", value: 900)]),
            ],
            tracksClaimedFees: false
        )
        #expect(overview.entries.map(\.wallet.name) == ["Trezor", "Main"])
        #expect(overview.entries.map(\.colorIndex) == [1, 0])
        #expect(overview.savedOrder.map(\.wallet.name) == ["Main", "Trezor"])
    }

    @Test func walletsStillLoadingComeLastAndStayOffTheBar() {
        let overview = WalletOverview(
            wallets: [(hot, nil), (main, [makePosition("1", value: 100)]), (trezor, [])],
            tracksClaimedFees: false
        )
        #expect(overview.entries.map(\.wallet.id) == [main.id, trezor.id, hot.id])
        #expect(overview.entries.last?.positions == nil)
        #expect(overview.barEntries.map(\.wallet.id) == [main.id])
    }

    @Test func countsPositionsThatNeedAttention() {
        let overview = WalletOverview(
            wallets: [(main, [
                makePosition("1", inRange: true, value: 10),
                makePosition("2", inRange: false, value: 10),
                makePosition("3", inRange: nil, value: 10),
            ])],
            tracksClaimedFees: false
        )
        #expect(overview.entries.first?.attentionCount == 2)
    }

    @Test func claimedFeesOnlyWhileTrackingIsOn() {
        let wallets: [(wallet: SavedWallet, positions: [Position]?)] = [
            (main, [makePosition("1", value: 100, fees: 2, claimed: 8)]),
        ]
        #expect(WalletOverview(wallets: wallets, tracksClaimedFees: false).feeSummary == nil)
        let summary = WalletOverview(wallets: wallets, tracksClaimedFees: true).feeSummary
        #expect(summary?.claimedUSD == 8)
        #expect(summary?.allTimeUSD == 10)
    }

    @Test func shareBarKeepsSmallWalletsVisibleWithinTheWidth() {
        let widths = WalletShareBar.widths([0.97, 0.02, 0.01], in: 200)
        let available: CGFloat = 200 - 2 * 2 - 2 * 2
        #expect(widths.allSatisfy { $0 >= 6 })
        #expect(abs(widths.reduce(0, +) - available) < 0.001)
        #expect(widths[0] > widths[1])
    }
}
