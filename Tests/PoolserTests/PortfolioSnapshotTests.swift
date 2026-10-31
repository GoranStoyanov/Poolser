import Foundation
import Testing
@testable import PoolserKit

private func makePosition(
    _ tokenId: String,
    chainID: String = "ethereum",
    inRange: Bool? = true,
    value: Double? = nil,
    fees: Double? = nil
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
    return p
}

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("Portfolio snapshot")
struct PortfolioSnapshotTests {
    @Test func totalsCoverEveryPosition() {
        let snapshot = PortfolioSnapshot(
            positions: [
                makePosition("1", value: 100, fees: 2),
                makePosition("2", chainID: "base", inRange: false, value: 50, fees: 1),
                makePosition("3", value: nil, fees: nil),
            ],
            dailyFeesUSD: [1, 2],
            updatedAt: now
        )
        #expect(snapshot.totalValueUSD == 150)
        #expect(snapshot.unclaimedFeesUSD == 3)
        #expect(snapshot.positionCount == 3)
        #expect(snapshot.attentionCount == 1)
        #expect(snapshot.chainCount == 2)
        #expect(snapshot.dailyFeesUSD == [1, 2])
    }

    @Test func itemsPutAttentionFirstThenValueAndIncludeEveryPosition() {
        let snapshot = PortfolioSnapshot(
            positions: [
                makePosition("1", value: 10),
                makePosition("2", value: 500),
                makePosition("3", inRange: false, value: 5),
                makePosition("4", value: 80),
                makePosition("5", value: 40),
            ],
            dailyFeesUSD: nil,
            updatedAt: now
        )
        #expect(snapshot.items.map(\.id) == [
            "ethereum-v3-3", "ethereum-v3-2", "ethereum-v3-4", "ethereum-v3-5", "ethereum-v3-1"
        ])
        #expect(snapshot.items.first?.status == .outOfRange)
        #expect(snapshot.items.first?.pairLabel == "WETH/USDC")
        #expect(snapshot.items.first?.chainName == "Ethereum")
    }

    @Test func roundTripsThroughTheFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortfolioSnapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var position = makePosition("1", value: 100, fees: 2)
        position.poolAddress = "0x1234"
        position.dec0 = 18
        position.dec1 = 6
        let snapshot = PortfolioSnapshot(positions: [position], dailyFeesUSD: [0.5], updatedAt: now)

        #expect(PortfolioSnapshotStore.save(snapshot, to: url))
        #expect(PortfolioSnapshotStore.load(from: url) == snapshot)
        #expect(snapshot.items[0].pool?.reference == "0x1234")
        #expect(snapshot.items[0].pool?.tickLower == -100)
        #expect(snapshot.items[0].pool?.token1Decimals == 6)

        #expect(PortfolioSnapshotStore.save(nil, to: url))
        #expect(PortfolioSnapshotStore.load(from: url) == nil)
    }

    @Test func snapshotWrittenBeforeWalletNamesStillLoads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = #"{"updatedAt":1800000000,"totalValueUSD":1,"unclaimedFeesUSD":0,"positionCount":0,"attentionCount":0,"chainCount":0,"items":[]}"#
        try Data(json.utf8).write(to: url)
        let snapshot = try #require(PortfolioSnapshotStore.load(from: url))
        #expect(snapshot.walletName == nil)
        #expect(snapshot.totalValueUSD == 1)
    }

    @Test func nothingIsWrittenWithoutAnAppGroup() {
        #expect(!PortfolioSnapshotStore.save(nil, to: nil))
        #expect(PortfolioSnapshotStore.load(from: nil) == nil)
    }
}

@Suite("Widget reload throttle")
struct WidgetReloadThrottleTests {
    private func snapshot(outOfRange: Bool = false, value: Double = 100, wallet: String? = nil) -> PortfolioSnapshot {
        PortfolioSnapshot(
            positions: [makePosition("1", inRange: !outOfRange, value: value)], dailyFeesUSD: nil, updatedAt: now,
            walletName: wallet
        )
    }

    @Test func walletChangeReloadsAtOnce() {
        var throttle = WidgetReloadThrottle()
        _ = throttle.shouldReload(for: snapshot(wallet: "Main"), now: now)
        let reloads = throttle.shouldReload(for: snapshot(wallet: "Cold"), now: now.addingTimeInterval(60))
        #expect(reloads)
    }

    @Test func firstSnapshotReloads() {
        var throttle = WidgetReloadThrottle()
        let reloads = throttle.shouldReload(for: snapshot(), now: now)
        #expect(reloads)
    }

    @Test func driftingValuesWaitForTheInterval() {
        var throttle = WidgetReloadThrottle()
        _ = throttle.shouldReload(for: snapshot(), now: now)
        let early = throttle.shouldReload(for: snapshot(value: 120), now: now.addingTimeInterval(5 * 60))
        #expect(!early)
        let afterInterval = throttle.shouldReload(
            for: snapshot(value: 130), now: now.addingTimeInterval(WidgetReloadThrottle.minimumInterval)
        )
        #expect(afterInterval)
    }

    @Test func rangeChangeReloadsAtOnce() {
        var throttle = WidgetReloadThrottle()
        _ = throttle.shouldReload(for: snapshot(), now: now)
        let reloads = throttle.shouldReload(for: snapshot(outOfRange: true), now: now.addingTimeInterval(60))
        #expect(reloads)
    }

    @Test func skippedReloadKeepsComparingToWhatWasShown() {
        var throttle = WidgetReloadThrottle()
        _ = throttle.shouldReload(for: snapshot(), now: now)
        // Skipped, so the widget still shows the in-range picture.
        let drifted = throttle.shouldReload(for: snapshot(value: 90), now: now.addingTimeInterval(60))
        #expect(!drifted)
        let rangeChanged = throttle.shouldReload(for: snapshot(outOfRange: true), now: now.addingTimeInterval(120))
        #expect(rangeChanged)
    }

    @Test func clearingReloadsOnceThenStays() {
        var throttle = WidgetReloadThrottle()
        _ = throttle.shouldReload(for: snapshot(), now: now)
        let cleared = throttle.shouldReload(for: nil, now: now.addingTimeInterval(60))
        #expect(cleared)
        let clearedAgain = throttle.shouldReload(for: nil, now: now.addingTimeInterval(120))
        #expect(!clearedAgain)
    }
}
