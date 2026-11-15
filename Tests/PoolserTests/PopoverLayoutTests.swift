import AppKit
import SwiftUI
import Testing
@testable import Poolser
@testable import PoolserKit

@Suite("Popover layout", .serialized)
@MainActor
struct PopoverLayoutTests {
    @Test(arguments: [620.0, 900.0, 1200.0], [DynamicTypeSize.large, .accessibility2])
    func sixPositionsKeepTheMenuCompact(_ screenHeight: Double, _ typeSize: DynamicTypeSize) async throws {
        var snapshot = GraphitePreviewData.snapshot
        snapshot.positions = (0..<6).map { index in
            GraphitePreviewData.position(
                chain: "ethereum", chainName: "Ethereum", chainNumericID: 1, tokenId: String(index),
                sym0: "WALLETH", sym1: "WETH", dec0: 18, dec1: 18, feeRaw: 10_000,
                lower: 0.000004204, upper: 0.000006026, current: 0.000006472,
                valueUSD: 2_000, feesUSD: 2, fees0: 1, fees1: 0.0002, apr: 24,
                amounts: (1, 0.5), volume: 100_000, tvl: 1_000_000,
                claimedUSD: 200, openedDaysAgo: 90
            )
        }
        snapshot.positionDailyFeesUSD = Dictionary(uniqueKeysWithValues: snapshot.positions.map {
            ($0.id, [1, 2, 1, 3, 2, 1, 2])
        })
        snapshot.feeSummary = WalletFeeSummary(positions: snapshot.positions)
        let wallet = SavedWallet(address: snapshot.walletAddress, name: "Anchor")
        snapshot.pages = [.allWallets, .wallet(wallet), .wallet(SavedWallet(address: "0x1111111111111111111111111111111111111111", name: "Tide"))]
        snapshot.shownPage = .wallet(wallet)
        let limit = GraphitePopover.heightLimit(for: screenHeight)
        let view = GraphitePopover(snapshot: snapshot, listOptions: .constant(PositionListOptions()),
                                   actions: GraphitePreviewData.actions, maxHeight: limit)
            .dynamicTypeSize(typeSize)
            .fixedSize()
        let size = try await fittingSize(view)
        #expect(size.width == 420)
        #expect(size.height <= min(720, screenHeight * 0.8) + 1)
        #expect(size.height > 300)
    }

    @Test func heightLimitStaysCompactWithoutAScreen() {
        #expect(GraphitePopover.heightLimit(for: nil) == 720)
    }

    @Test func onePositionDoesNotStretchToTheLimit() async throws {
        var snapshot = GraphitePreviewData.snapshot
        snapshot.positions = [snapshot.positions[1]]
        snapshot.dailyFeesUSD = nil
        snapshot.feeSummary = nil
        let view = GraphitePopover(snapshot: snapshot, listOptions: .constant(PositionListOptions()),
                                   maxHeight: GraphitePopover.heightLimit(for: 1200))
            .fixedSize()
        let size = try await fittingSize(view)
        #expect(size.height < 500)
    }

    @Test(arguments: [420.0, 620.0, 900.0])
    func staysWithinScreenHeight(_ limit: Double) async throws {
        var snapshot = GraphitePreviewData.snapshot
        snapshot.lastError = String(repeating: "RPC unavailable. Showing the last successful update. ", count: 8)
        let view = GraphitePopover(snapshot: snapshot, listOptions: .constant(PositionListOptions()),
                                   actions: GraphitePreviewData.actions, maxHeight: limit)
            .dynamicTypeSize(.accessibility2)
        let size = try await fittingSize(view)
        #expect(size.width == 420)
        #expect(size.height <= limit + 1)
        #expect(size.height > 100)
    }

    @Test func compactSummaryKeepsRoomForPositions() async throws {
        let snapshot = GraphitePreviewData.snapshot
        let view = PortfolioSummaryCard(positions: snapshot.positions, dailyFees: snapshot.dailyFeesUSD,
                                        feeSummary: snapshot.feeSummary) { EmptyView() }
            .frame(width: 396)
        let size = try await fittingSize(view)
        #expect(size.height < 300)
        #expect(size.height > 200)
    }

    @Test func collectFitsWithoutAnExtraFooterRow() async throws {
        let position = GraphitePreviewData.positions[1]
        let history = [9.0, 11, 8, 13, 12, 10, 14]
        let ordinary = GraphitePositionCard(position: position, recentDailyFees: history)
            .frame(width: 396)
        let collectable = GraphitePositionCard(position: position, recentDailyFees: history, onCollect: {})
            .frame(width: 396)
        let ordinarySize = try await fittingSize(ordinary)
        let collectableSize = try await fittingSize(collectable)
        #expect(collectableSize.height < 230)
        #expect(collectableSize.height - ordinarySize.height <= 12)
    }

    private func fittingSize<V: View>(_ view: V) async throws -> CGSize {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 900),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        defer { window.close() }
        // Geometry measurements settle across layout passes, including the list viewport.
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(100))
            window.setContentSize(hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
        }
        return hosting.fittingSize
    }
}
