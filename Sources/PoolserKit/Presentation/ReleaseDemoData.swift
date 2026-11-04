#if DEBUG
import Foundation

/// Public, fictional positions for native iOS App Store captures. Never uses a wallet or API key.
public enum ReleaseDemoData {
    public static let positions: [Position] = [
        make(chain: "base", name: "Base", id: 8453, token: "198220", v4: true,
             tokens: ("0x4200000000000000000000000000000000000006", "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"),
             symbols: ("ETH", "USDC"), decimals: (18, 6), fee: 500,
             range: (3_250, 3_570, 3_544), amounts: (0.82, 6_309.02),
             value: 9_215.10, unclaimed: 191.03, claimed: nil, apr: 41.7,
             prices: (3_544, 1), volume: 18_200_000, tvl: 6_400_000),
        make(chain: "ethereum", name: "Ethereum", id: 1, token: "812345", v4: false,
             tokens: ("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"),
             symbols: ("USDC", "WETH"), decimals: (6, 18), fee: 500,
             range: (1 / 3_980, 1 / 3_120, 1 / 3_544), amounts: (10_740, 3.030536),
             value: 21_480.22, unclaimed: 84.12, claimed: 1_086.20, apr: 18.4,
             prices: (1, 3_544), volume: 142_000_000, tvl: 280_000_000),
        make(chain: "unichain", name: "Unichain", id: 130, token: "50331", v4: false,
             tokens: ("0x1f9840a85d5af5bf1d1762f925bdaddc4201f984", "0x4200000000000000000000000000000000000006"),
             symbols: ("UNI", "WETH"), decimals: (18, 18), fee: 3_000,
             range: (nil, nil, 0.00206), amounts: (315.8, 0.648891),
             value: 4_611.33, unclaimed: 25.03, claimed: nil, apr: 9.2,
             prices: (7.32, 3_544), volume: 1_100_000, tvl: 4_600_000),
        make(chain: "arbitrum", name: "Arbitrum", id: 42161, token: "4412870", v4: false,
             tokens: ("0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f", "0x82af49447d8a07e3bd95bd0d56f35241523fbab1"),
             symbols: ("WBTC", "WETH"), decimals: (8, 18), fee: 3_000,
             range: (27.10, 29.40, 25.96), amounts: (0.140291, 0),
             value: 12_906.75, unclaimed: 12.40, claimed: 22.15, apr: 6.3,
             prices: (92_000, 3_544), volume: 3_900_000, tvl: 31_000_000),
    ]

    public static var dailyFees: DailyFees {
        var result = DailyFees()
        let calendar = Calendar.current
        for position in positions {
            let dailyUSD = (position.usd ?? 0) / 18
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: .now),
                      let price = position.price0USD else { continue }
                result.byPosition[position.id, default: [:]][DailyFeeLedger.dayKey(day, calendar: calendar)] =
                    .init(token0: dailyUSD * (offset == 0 ? 0.55 : 1) / price, token1: 0)
            }
        }
        return result
    }

    private static func make(
        chain: String, name: String, id: Int, token: String, v4: Bool,
        tokens: (String, String), symbols: (String, String), decimals: (Int, Int), fee: Int,
        range: (Double?, Double?, Double), amounts: (Double, Double),
        value: Double, unclaimed: Double, claimed: Double?, apr: Double,
        prices: (Double, Double), volume: Double, tvl: Double
    ) -> Position {
        let lower = range.0.map { tick($0, decimals) } ?? -887_220
        let upper = range.1.map { tick($0, decimals) } ?? 887_220
        let current = tick(range.2, decimals)
        var position = Position(chainID: chain, chainName: name, chainNumericID: id, tokenId: token,
                                token0: tokens.0, token1: tokens.1, sym0: symbols.0, sym1: symbols.1,
                                feePct: V4Fee.label(fee), feeRaw: fee,
                                fees0: unclaimed / 2 / prices.0, fees1: unclaimed / 2 / prices.1,
                                tickLower: lower, tickUpper: upper, liquidity: 1)
        position.isV4 = v4
        position.dec0 = decimals.0
        position.dec1 = decimals.1
        position.currentTick = current
        position.inRange = Position.isInRange(tick: current, lower: lower, upper: upper)
        position.amount0 = amounts.0
        position.amount1 = amounts.1
        position.positionUSD = value
        position.usd = unclaimed
        position.claimedUSD = claimed
        position.openedAt = Date().addingTimeInterval(-80 * 86_400)
        position.feeAPR = apr
        position.price0USD = prices.0
        position.price1USD = prices.1
        position.volumeUSD24h = volume
        position.tvlUSD = tvl
        return position
    }

    private static func tick(_ price: Double, _ decimals: (Int, Int)) -> Int {
        Int((log(price) - Double(decimals.0 - decimals.1) * log(10)) / log(1.0001))
    }
}
#endif
