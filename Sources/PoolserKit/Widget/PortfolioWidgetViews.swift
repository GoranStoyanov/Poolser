import SwiftUI

/// Widget layouts for a `PortfolioSnapshot`. Plain SwiftUI so the macOS and iOS widget
/// extensions share them and they render outside WidgetKit; each extension adds its own
/// container background.
public struct PortfolioWidgetView: View {
    public enum Size { case small, medium }

    /// After this long without a new snapshot the timestamp turns amber: the app is probably
    /// not running.
    public static let staleAfter: TimeInterval = 60 * 60

    let snapshot: PortfolioSnapshot?
    let size: Size
    /// When the view is shown, for the stale check.
    let date: Date

    @Environment(\.colorScheme) private var colorScheme

    public init(snapshot: PortfolioSnapshot?, size: Size, date: Date) {
        self.snapshot = snapshot
        self.size = size
        self.date = date
    }

    public var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        ZStack(alignment: .topTrailing) {
            PoolBrandRibbon(animated: false, compact: true)
                .padding(.top, -16)
                .padding(.trailing, -16)
            if let snapshot, snapshot.positionCount > 0 {
                switch size {
                case .small:
                    Summary(snapshot: snapshot, date: date, palette: palette)
                case .medium:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 14) {
                            Summary(snapshot: snapshot, date: date, palette: palette, compact: true)
                                .frame(maxWidth: 132, alignment: .leading)
                            if let daily = snapshot.dailyFeesUSD, !daily.isEmpty {
                                WeekFees(values: Array(daily.suffix(14)), palette: palette)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                    .padding(.top, 24)
                            } else {
                                PositionList(snapshot: snapshot, palette: palette)
                                    .padding(.top, 24)
                            }
                        }
                        Rectangle().fill(palette.cardLine).frame(height: 0.5)
                        HStack(spacing: 8) {
                            Text("Portfolio \(PositionPresentation.compactUSD(snapshot.totalValueUSD))")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(palette.primaryText)
                            Spacer(minLength: 0)
                            RangeLine(snapshot: snapshot, palette: palette)
                        }
                    }
                }
            } else {
                EmptyState(hasSnapshot: snapshot != nil, walletName: snapshot?.walletName, palette: palette)
                    .padding(.top, 18)
            }
        }
    }
}

private struct Summary: View {
    let snapshot: PortfolioSnapshot
    let date: Date
    let palette: GraphitePalette

    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(walletName: snapshot.walletName, palette: palette)
                .padding(.trailing, 24)
            Spacer(minLength: 5)
            Text("Unclaimed fees")
                .font(.caption2).foregroundStyle(palette.secondaryText)
            Text(formatUSD(snapshot.unclaimedFeesUSD))
                .font(PoolTypography.amount(compact ? 25 : 30))
                .foregroundStyle(palette.primaryText)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let today = snapshot.dailyFeesUSD?.last {
                Text("+\(formatUSD(today)) today")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.fees)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 5)
            if !compact {
                RangeLine(snapshot: snapshot, palette: palette)
            }
            Updated(updatedAt: snapshot.updatedAt, date: date, palette: palette)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The app's name, or the wallet's once there is more than one.
private struct Header: View {
    let walletName: String?
    let palette: GraphitePalette

    var body: some View {
        HStack(spacing: 5) {
            PoolEyes().scaleEffect(0.8).frame(width: 16, height: 12)
            Text(walletName ?? "Poolser")
                .font(PoolTypography.heading(12, relativeTo: .caption))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
        }
    }
}

/// "3 of 4 in range" when all is well, otherwise how many need attention, in that colour.
private struct RangeLine: View {
    let snapshot: PortfolioSnapshot
    let palette: GraphitePalette

    var body: some View {
        let attention = snapshot.attentionCount
        let worst = snapshot.items.first(where: { $0.status.needsAttention })?.status ?? .inRange
        let colors = palette.status(attention > 0 ? worst : .inRange)
        HStack(spacing: 5) {
            Circle().fill(colors.tint).frame(width: 6, height: 6)
            Text(attention > 0
                 ? "\(attention) need\(attention == 1 ? "s" : "") attention"
                 : "\(snapshot.positionCount) of \(snapshot.positionCount) in range")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(colors.tint)
                .lineLimit(1)
        }
    }
}

private struct Updated: View {
    let updatedAt: Date
    let date: Date
    let palette: GraphitePalette

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        let stale = date.timeIntervalSince(updatedAt) > PortfolioWidgetView.staleAfter
        // Fixed per timeline entry: a live relative date counts seconds, which is noise here.
        Text(date.timeIntervalSince(updatedAt) < 60
             ? "Updated just now"
             : "Updated \(Self.formatter.localizedString(for: updatedAt, relativeTo: date))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(stale ? palette.nearEdge.tint : palette.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct PositionList: View {
    let snapshot: PortfolioSnapshot
    let palette: GraphitePalette

    private static let rows = 3

    var body: some View {
        let shown = snapshot.items.prefix(Self.rows)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(shown) { item in
                PositionRow(item: item, palette: palette)
            }
            let more = snapshot.positionCount - shown.count
            if more > 0 {
                Text("+\(more) more")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 0)
            // Room left under one or two positions goes to the week's fees.
            if shown.count < Self.rows, let daily = snapshot.dailyFeesUSD, daily.count > 1 {
                WeekFees(values: daily, palette: palette)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PositionRow: View {
    let item: PortfolioSnapshot.Item
    let palette: GraphitePalette

    var body: some View {
        let colors = palette.status(item.status)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(colors.tint).frame(width: 6, height: 6)
                Text(item.pairLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(item.chainName)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.valueUSD.map(PositionPresentation.compactUSD) ?? "–")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            HStack(spacing: 6) {
                MiniRangeGauge(gauge: item.gauge, colors: colors, track: palette.track)
                if let label = item.distanceLabel ?? (item.status == .inRange ? nil : item.status.title) {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }
}

/// Fees per day, scaled to the best day; the last bar is today.
private struct WeekFees: View {
    let values: [Double]
    let palette: GraphitePalette

    var body: some View {
        let peak = values.max() ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Fees, \(values.count) days")
                Spacer(minLength: 4)
                Text(formatUSD(values.reduce(0, +)))
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(palette.secondaryText)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index == values.count - 1 ? palette.barToday : palette.bar)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, peak > 0 ? 42 * value / peak : 3))
                }
            }
            .frame(height: 42, alignment: .bottom)
        }
    }
}

private struct EmptyState: View {
    let hasSnapshot: Bool
    let walletName: String?
    let palette: GraphitePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(walletName: walletName, palette: palette)
            Spacer(minLength: 0)
            Text(hasSnapshot ? "No positions" : "No data yet")
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.primaryText)
            Text(hasSnapshot
                 ? "This wallet has no Uniswap positions on the enabled networks."
                 : "Open Poolser and add a wallet to see your positions here.")
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

extension PortfolioSnapshot {
    /// Fixed data for widget placeholders, previews and the gallery.
    public static let preview = PortfolioSnapshot(
        updatedAt: Date(),
        totalValueUSD: 48_213.40,
        unclaimedFeesUSD: 312.58,
        dailyFeesUSD: [31, 24, 19, 35, 41, 28, 33],
        positionCount: 4,
        attentionCount: 2,
        chainCount: 4,
        items: [
            Item(id: "arbitrum-v3-4412870", pairLabel: "WBTC/WETH", chainName: "Arbitrum", valueUSD: 12_906.75,
                 feesUSD: 12.40, status: .outOfRange, distanceLabel: "4.2% below",
                 gauge: RangeGaugeLayout(bandStart: 0.35, bandEnd: 0.9, marker: 0.08, isMarkerClamped: false)),
            Item(id: "base-v4-198220", pairLabel: "ETH/USDC", chainName: "Base", valueUSD: 9_215.10,
                 feesUSD: 191.03, status: .nearMax,
                 gauge: RangeGaugeLayout(bandStart: 0.1, bandEnd: 0.88, marker: 0.86, isMarkerClamped: false)),
            Item(id: "ethereum-v3-812345", pairLabel: "WETH/USDC", chainName: "Ethereum", valueUSD: 21_480.22,
                 feesUSD: 84.12, status: .inRange,
                 gauge: RangeGaugeLayout(bandStart: 0.12, bandEnd: 0.82, marker: 0.55, isMarkerClamped: false)),
            Item(id: "unichain-v3-50331", pairLabel: "UNI/WETH", chainName: "Unichain", valueUSD: 4_611.33,
                 feesUSD: 25.03, status: .fullRange,
                 gauge: RangeGaugeLayout(bandStart: 0, bandEnd: 1, marker: 0.5, isMarkerClamped: false)),
        ]
    )
}
