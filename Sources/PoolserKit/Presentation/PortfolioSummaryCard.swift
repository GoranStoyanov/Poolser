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
        .compositingGroup()
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
                    SummaryMetric(title: "Claimed", value: formatUSD(summary.claimedUSD), explanation: claimedHelp)
                    Spacer(minLength: 0)
                    if let level = summary.returnOnAssets { SummaryMetric(title: "Pool level", value: formatPercent(level), explanation: poolHelp) }
                    Spacer(minLength: 0)
                    if let apr = summary.realizedAPR { SummaryMetric(title: "APR", value: formatPercent(apr), explanation: aprHelp) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SummaryMetric(title: "Claimed", value: formatUSD(summary.claimedUSD), explanation: claimedHelp)
                    if let level = summary.returnOnAssets { SummaryMetric(title: "Pool level", value: formatPercent(level), explanation: poolHelp) }
                    if let apr = summary.realizedAPR { SummaryMetric(title: "APR", value: formatPercent(apr), explanation: aprHelp) }
                }
            }
        }
    }

    private var claimedHelp: String {
        "Fees already collected from v3 positions, valued at current token prices. Claimed v4 fees are not tracked."
    }

    private var poolHelp: String {
        "All-time fees (claimed + unclaimed) ÷ current position value × 100. Only positions with known fees and value are included.\n\nThe water fills the card from bottom to top: 0% is empty, 50% is halfway, and 100% is full. Above 100% the card stays full; the percentage still shows the actual return.\n\nChanges in token prices or liquidity also change the level."
    }

    private var aprHelp: String {
        "Annualized fee return since opening, weighted by each position’s current value and age.\n\nΣ all-time fees ÷ Σ (current position value × years open) × 100.\n\nOnly positions with known fees, value and an opening date at least one day ago are included. Claimed fees use current token prices. Liquidity changes affect the estimate; this is not a forecast."
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let explanation: String
    @State private var showingExplanation = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = GraphitePalette.current(scheme)
        Button { showingExplanation.toggle() } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 3) {
                    Text(title)
                    Image(systemName: "info.circle").imageScale(.small)
                }
                .font(.caption2).foregroundStyle(palette.primaryText)
                Text(value).font(PoolTypography.amount(16, relativeTo: .callout))
                    .foregroundStyle(palette.primaryText)
            }
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Show explanation")
        .help(explanation)
        .popover(isPresented: $showingExplanation) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(PoolTypography.heading(16))
                Text(explanation).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(idealWidth: 280, maxWidth: 320, alignment: .leading)
            .foregroundStyle(palette.primaryText)
            .background(palette.card)
            .presentationCompactAdaptation(.popover)
        }
    }
}
