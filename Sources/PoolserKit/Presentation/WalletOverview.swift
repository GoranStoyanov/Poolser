import Foundation

/// What the All Wallets page shows: every saved wallet with its positions and the totals across
/// them. Built from each wallet's last load, so it needs no reload when the page changes.
public struct WalletOverview {
    public struct Entry: Identifiable {
        public let wallet: SavedWallet
        /// The wallet's place in the saved list, which picks its colour; stays put when values change.
        public let colorIndex: Int
        /// Nil until the wallet's first load finishes.
        public let positions: [Position]?
        public let valueUSD: Double
        public let unclaimedFeesUSD: Double
        /// The wallet's part of the total value, 0…1.
        public let share: Double
        /// Positions out of range, near an edge or with an unknown range.
        public let attentionCount: Int

        public var id: String { wallet.id }
    }

    /// Largest wallet first; wallets still loading come last, in saved order.
    public let entries: [Entry]
    public let totalValueUSD: Double
    public let unclaimedFeesUSD: Double
    /// Claimed and all-time fees with the pool level; nil while claimed-fee tracking is off.
    public let feeSummary: WalletFeeSummary?
    public let positionCount: Int
    public let chainCount: Int

    /// `wallets` in saved order, each with its positions or nil while it is still loading.
    public init(wallets: [(wallet: SavedWallet, positions: [Position]?)], tracksClaimedFees: Bool, now: Date = Date()) {
        let all = wallets.flatMap { $0.positions ?? [] }
        let total = all.compactMap(\.positionUSD).reduce(0, +)
        totalValueUSD = total
        unclaimedFeesUSD = all.compactMap(\.usd).reduce(0, +)
        feeSummary = tracksClaimedFees && !all.isEmpty ? WalletFeeSummary(positions: all, now: now) : nil
        positionCount = all.count
        chainCount = Set(all.map(\.chainID)).count

        let unsorted = wallets.enumerated().map { index, item in
            let positions = item.positions ?? []
            let value = positions.compactMap(\.positionUSD).reduce(0, +)
            return Entry(
                wallet: item.wallet,
                colorIndex: index,
                positions: item.positions,
                valueUSD: value,
                unclaimedFeesUSD: positions.compactMap(\.usd).reduce(0, +),
                share: total > 0 ? value / total : 0,
                attentionCount: positions.filter { $0.error == nil && PositionPresentation($0).status.needsAttention }.count
            )
        }
        entries = unsorted.sorted { lhs, rhs in
            switch (lhs.positions == nil, rhs.positions == nil) {
            case (false, true): return true
            case (true, false): return false
            default: return lhs.valueUSD == rhs.valueUSD ? lhs.colorIndex < rhs.colorIndex : lhs.valueUSD > rhs.valueUSD
            }
        }
    }

    /// Wallets with value, in the order the share bar draws them.
    public var barEntries: [Entry] { entries.filter { $0.share > 0 } }

    /// Every wallet in saved order, for the header's colour marks.
    public var savedOrder: [Entry] { entries.sorted { $0.colorIndex < $1.colorIndex } }
}
