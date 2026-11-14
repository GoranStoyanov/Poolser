import AppKit
import SwiftUI
import Testing
@testable import Poolser
@testable import PoolserKit

@Suite("Popover layout", .serialized)
@MainActor
struct PopoverLayoutTests {
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
