#if DEBUG
import SwiftUI

/// Fixed positions for previews: one near the edge, one in range with an inverted pair, one full
/// range and one out of range, so every status shows at once.
enum GraphitePreviewData {
    static let ethPrice = 3_544.0

    static let positions: [Position] = [
        position(
            chain: "base", chainName: "Base", chainNumericID: 8453, tokenId: "198220", isV4: true,
            sym0: "ETH", sym1: "USDC", dec0: 18, dec1: 6, feeRaw: 500,
            lower: 3_250, upper: 3_570, current: ethPrice,
            valueUSD: 9_215.10, feesUSD: 191.03, fees0: 0.0287, fees1: 89.30, apr: 41.7,
            amounts: (0.82, 6_309), volume: 18_200_000, tvl: 6_400_000
        ),
        // USDC sorts before WETH on Ethereum, so the pool prices WETH per USDC and the view inverts it.
        position(
            chain: "ethereum", chainName: "Ethereum", chainNumericID: 1, tokenId: "812345",
            sym0: "USDC", sym1: "WETH", dec0: 6, dec1: 18, feeRaw: 500,
            lower: 1 / 3_980, upper: 1 / 3_120, current: 1 / ethPrice,
            valueUSD: 21_480.22, feesUSD: 84.12, fees0: 33.80, fees1: 0.0142, apr: 18.4,
            amounts: (10_740, 3.0306), volume: 142_000_000, tvl: 280_000_000,
            claimedUSD: 1_086.20, openedDaysAgo: 214
        ),
        position(
            chain: "unichain", chainName: "Unichain", chainNumericID: 130, tokenId: "50331",
            sym0: "UNI", sym1: "WETH", dec0: 18, dec1: 18, feeRaw: 3_000,
            lower: nil, upper: nil, current: 0.00206,
            valueUSD: 4_611.33, feesUSD: 25.03, fees0: 1.92, fees1: 0.0031, apr: 9.2,
            amounts: (315.8, 0.6507), volume: 1_100_000, tvl: 4_600_000
        ),
        position(
            chain: "arbitrum", chainName: "Arbitrum", chainNumericID: 42161, tokenId: "4412870",
            sym0: "WBTC", sym1: "WETH", dec0: 8, dec1: 18, feeRaw: 3_000,
            lower: 27.10, upper: 29.40, current: 25.96,
            valueUSD: 12_906.75, feesUSD: 12.40, fees0: 0.00009, fees1: 0.00116, apr: 6.3,
            amounts: (0.1403, 0), volume: 3_900_000, tvl: 31_000_000,
            claimedUSD: 22.15, openedDaysAgo: 41
        ),
    ]

    static let snapshot = PortfolioSnapshot(
        walletAddress: "0x8f3c4b1e9d2a7c6f5e0b3a8d1c4e7f2a9b6da21c",
        positions: positions,
        dailyFeesUSD: [12, 16, 14, 20, 17, 23, 19, 26, 21, 24, 18, 22, 15, 27,
                       31, 24, 19, 35, 41, 28, 33, 38, 29, 37, 30, 34, 36, 39, 33, 41.20],
        positionDailyFeesUSD: [
            positions[0].id: [22, 25, 19, 28, 31, 27, 30],
            positions[1].id: [9, 11, 8, 13, 12, 10, 14],
            positions[2].id: [3, 4, 3, 5, 4, 3, 4],
            positions[3].id: [6, 5, 3, 1, 0, 0, 0],
        ],
        lastUpdated: Date().addingTimeInterval(-120),
        feeSummary: WalletFeeSummary(positions: positions)
    )

    static let actions = GraphitePopoverActions(
        refresh: {}, settings: {}, logs: {}, quit: {}, open: { _ in }, collect: { _ in }
    )

    /// Prices are token1 per token0 in whole tokens; nil bounds make a full-range position.
    private static func position(
        chain: String, chainName: String, chainNumericID: Int, tokenId: String, isV4: Bool = false,
        sym0: String, sym1: String, dec0: Int, dec1: Int, feeRaw: Int,
        lower: Double?, upper: Double?, current: Double,
        valueUSD: Double, feesUSD: Double, fees0: Double, fees1: Double, apr: Double,
        amounts: (Double, Double), volume: Double, tvl: Double,
        claimedUSD: Double? = nil, openedDaysAgo: Double? = nil
    ) -> Position {
        let tickLower = lower.map { tick(price: $0, dec0: dec0, dec1: dec1) } ?? -887_220
        let tickUpper = upper.map { tick(price: $0, dec0: dec0, dec1: dec1) } ?? 887_220
        let currentTick = tick(price: current, dec0: dec0, dec1: dec1)
        var pos = Position(
            chainID: chain, chainName: chainName, chainNumericID: chainNumericID, tokenId: tokenId,
            token0: "0x0", token1: "0x1", sym0: sym0, sym1: sym1,
            feePct: V4Fee.label(feeRaw), feeRaw: feeRaw, fees0: fees0, fees1: fees1,
            tickLower: tickLower, tickUpper: tickUpper, liquidity: 1
        )
        pos.dec0 = dec0
        pos.dec1 = dec1
        pos.usd = feesUSD
        pos.positionUSD = valueUSD
        pos.currentTick = currentTick
        pos.inRange = Position.isInRange(tick: currentTick, lower: tickLower, upper: tickUpper)
        pos.isV4 = isV4
        pos.feeAPR = apr
        pos.amount0 = amounts.0
        pos.amount1 = amounts.1
        pos.volumeUSD24h = volume
        pos.tvlUSD = tvl
        if let claimedUSD {
            pos.claimedUSD = claimedUSD
            pos.claimedFees1 = claimedUSD / ethPrice
        }
        pos.openedAt = openedDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }
        return pos
    }

    private static func tick(price: Double, dec0: Int, dec1: Int) -> Int {
        Int((log(price) - Double(dec0 - dec1) * log(10)) / log(1.0001))
    }
}

/// Holds the list options in state so filters and sorting work in the canvas.
private struct PreviewPopover: View {
    var snapshot = GraphitePreviewData.snapshot
    @State private var options = PositionListOptions()

    var body: some View {
        GraphitePopover(snapshot: snapshot, listOptions: $options, actions: GraphitePreviewData.actions)
    }
}

#Preview("Popover · light") {
    PreviewPopover()
        .preferredColorScheme(.light)
}

#Preview("Popover · dark") {
    PreviewPopover()
        .preferredColorScheme(.dark)
}

#Preview("Popover · live data shape") {
    // What the app passes today: no daily history, no collect handler.
    var snapshot = GraphitePreviewData.snapshot
    snapshot.dailyFeesUSD = nil
    snapshot.positionDailyFeesUSD = [:]
    snapshot.lastError = "Arbitrum: HTTP 429: rate exceeded"
    return PreviewPopover(snapshot: snapshot)
}

#Preview("Popover · loading") {
    PreviewPopover(snapshot: PortfolioSnapshot(walletAddress: "0x8f3c4b1e9d2a7c6f5e0b3a8d1c4e7f2a9b6da21c",
                                               positions: [], isLoading: true))
}
#endif
