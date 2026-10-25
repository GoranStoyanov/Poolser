import Foundation
import Testing
@testable import Poolser

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let year: TimeInterval = 365.25 * 24 * 3600

private func makePosition(
    value: Double?, unclaimed: Double?, claimed: Double? = nil, claimedTokens: Double = 0,
    openedYearsAgo: Double?, error: String? = nil
) -> Position {
    var p = Position(
        chainID: "ethereum", chainName: "Ethereum", chainNumericID: 1,
        tokenId: "1", token0: "", token1: "",
        sym0: "A", sym1: "B", feePct: "0.30", feeRaw: 3_000,
        fees0: 0, fees1: 0, tickLower: -100, tickUpper: 100,
        liquidity: 1,
        error: error
    )
    p.positionUSD = value
    p.usd = unclaimed
    p.claimedUSD = claimed
    p.claimedFees0 = claimedTokens
    p.openedAt = openedYearsAgo.map { now.addingTimeInterval(-$0 * year) }
    return p
}

@Suite("Realized fee return")
struct RealizedReturnTests {
    @Test func returnOnAssetsAndAPRSinceOpen() throws {
        let p = makePosition(value: 10_000, unclaimed: 300, claimed: 1_500, claimedTokens: 1, openedYearsAgo: 8.0 / 12)
        #expect(p.allTimeFeesUSD == 1_800)
        #expect(p.feeReturnOnAssets == 0.18)
        let apr = try #require(p.realizedAPR(at: now))
        #expect(abs(apr - 0.27) < 1e-9)
    }

    @Test func noClaimsCountAsZeroOnceHistoryIsComplete() {
        let p = makePosition(value: 1_000, unclaimed: 50, openedYearsAgo: 1)
        #expect(p.feeReturnOnAssets == 0.05)
    }

    @Test func nothingBeforeTheHistoryIsComplete() {
        let p = makePosition(value: 1_000, unclaimed: 50, openedYearsAgo: nil)
        #expect(p.allTimeFeesUSD == nil)
        #expect(p.realizedAPR(at: now) == nil)
    }

    @Test func nothingUnclaimedCountsAsZero() throws {
        let p = makePosition(value: 1_000, unclaimed: nil, claimed: 150, claimedTokens: 1, openedYearsAgo: 1)
        #expect(p.allTimeFeesUSD == 150)
        let apr = try #require(p.realizedAPR(at: now))
        #expect(abs(apr - 0.15) < 1e-9)

        let summary = WalletFeeSummary(positions: [p], now: now)
        #expect(summary.returnOnAssets == 0.15)
    }

    @Test func unpricedOrFailedUnclaimedFeesHideTheReturn() {
        var unpriced = makePosition(value: 1_000, unclaimed: nil, claimed: 150, claimedTokens: 1, openedYearsAgo: 1)
        unpriced.fees0 = 3
        #expect(unpriced.allTimeFeesUSD == nil)

        var failed = makePosition(value: 1_000, unclaimed: nil, claimed: 150, claimedTokens: 1, openedYearsAgo: 1)
        failed.feesError = "fee read failed"
        #expect(failed.allTimeFeesUSD == nil)
    }

    @Test func unpricedClaimsHideTheReturn() {
        let p = makePosition(value: 1_000, unclaimed: 50, claimed: nil, claimedTokens: 2, openedYearsAgo: 1)
        #expect(p.allTimeFeesUSD == nil)
    }

    @Test func closedPositionHasNoReturn() {
        #expect(makePosition(value: 0, unclaimed: 50, openedYearsAgo: 1).feeReturnOnAssets == nil)
        #expect(makePosition(value: nil, unclaimed: 50, openedYearsAgo: 1).feeReturnOnAssets == nil)
    }

    @Test func positionYoungerThanADayGetsNoAPR() {
        let p = makePosition(value: 1_000, unclaimed: 5, openedYearsAgo: 0.5 / 365.25)
        #expect(p.feeReturnOnAssets == 0.005)
        #expect(p.realizedAPR(at: now) == nil)
    }

    @Test func walletAPRWeighsByValueAndTime() throws {
        let summary = WalletFeeSummary(positions: [
            makePosition(value: 10_000, unclaimed: 1_800, openedYearsAgo: 1),
            makePosition(value: 1_000, unclaimed: 500, openedYearsAgo: 0.5),
            makePosition(value: 5_000, unclaimed: 99, openedYearsAgo: nil),       // history incomplete: left out
            makePosition(value: 9_999, unclaimed: 999, openedYearsAgo: 1, error: "read failed"),
        ], now: now)
        let roa = try #require(summary.returnOnAssets)
        let apr = try #require(summary.realizedAPR)
        #expect(abs(roa - 2_300.0 / 11_000) < 1e-9)
        #expect(abs(apr - 2_300.0 / (10_000 * 1 + 1_000 * 0.5)) < 1e-9)
    }

    @Test func walletWithoutCompleteHistoryHasNoReturn() {
        let summary = WalletFeeSummary(positions: [makePosition(value: 1_000, unclaimed: 50, openedYearsAgo: nil)], now: now)
        #expect(summary.returnOnAssets == nil)
        #expect(summary.realizedAPR == nil)
    }
}
