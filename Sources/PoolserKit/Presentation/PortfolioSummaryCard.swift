import SwiftUI

/// Shared financial hierarchy for one wallet on Mac and iPhone.
public struct PortfolioSummaryCard<Actions: View>: View {
    let positions: [Position]
    let dailyFees: [Double]?
    let feeSummary: WalletFeeSummary?
    let actions: Actions
    @State private var days = 14
    @Environment(\.colorScheme) private var scheme
    private var palette: GraphitePalette { .current(scheme) }

    public init(positions: [Position], dailyFees: [Double]?, feeSummary: WalletFeeSummary?,
                @ViewBuilder actions: () -> Actions) {
        self.positions = positions
        self.dailyFees = dailyFees
        self.feeSummary = feeSummary
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PoolBrandRibbon()
                .padding(.horizontal, -16)
                .padding(.top, -16)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    fees
                    Spacer(minLength: 0)
                    value
                }
                VStack(alignment: .leading, spacing: 12) { fees; value }
            }
            if let dailyFees, !dailyFees.isEmpty {
                FeeHistoryChart(values: dailyFees, days: $days)
            }
            if let summary = feeSummary {
                if summary.isSyncing {
                    Label("Claimed fees syncing…", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                } else {
                    stats(summary)
                }
            }
        }
        .padding(16)
        .background {
            ZStack {
                palette.card
                if let summary = feeSummary, !summary.isSyncing, let level = summary.returnOnAssets {
                    PoolWater(level: level)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(palette.cardLine, lineWidth: 0.75))
    }

    private var fees: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Unclaimed fees").font(.caption).foregroundStyle(palette.secondaryText)
            Text(formatUSD(positions.compactMap(\.usd).reduce(0, +)))
                .font(PoolTypography.amount(32, relativeTo: .largeTitle))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let today = dailyFees?.last {
                Text("Today +\(formatUSD(today))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.fees)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var value: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("Total value").font(.caption).foregroundStyle(palette.secondaryText)
            Text(formatUSD(positions.compactMap(\.positionUSD).reduce(0, +)))
                .font(PoolTypography.amount(20, relativeTo: .title3))
                .foregroundStyle(palette.primaryText)
                .lineLimit(1).minimumScaleFactor(0.7)
            actions
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func stats(_ summary: WalletFeeSummary) -> some View {
        VStack(spacing: 10) {
            Rectangle().fill(palette.cardLine).frame(height: 0.5)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    stat("Claimed", formatUSD(summary.claimedUSD))
                    Spacer(minLength: 0)
                    if let level = summary.returnOnAssets { stat("Pool level", formatPercent(level)) }
                    Spacer(minLength: 0)
                    if let apr = summary.realizedAPR { stat("APR", formatPercent(apr)) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    stat("Claimed", formatUSD(summary.claimedUSD))
                    if let level = summary.returnOnAssets { stat("Pool level", formatPercent(level)) }
                    if let apr = summary.realizedAPR { stat("APR", formatPercent(apr)) }
                }
            }
            DisclosureGroup("Fee context") {
                Text("All-time fees \(formatUSD(summary.allTimeUSD)). Claimed v3 fees are valued at current prices; v4 claimed fees are not tracked. Pool level is all-time fees divided by current value. APR annualizes that return since opening and is not a forecast.")
                    .font(.caption).foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption2)
            .tint(palette.fees)
            .foregroundStyle(palette.secondaryText)
            .help("All-time \(formatUSD(summary.allTimeUSD)). Pool level: all-time fees / current value. APR: realized return annualized since opening.")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(palette.secondaryText)
            Text(value).font(PoolTypography.amount(16, relativeTo: .callout)).foregroundStyle(palette.primaryText)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}
