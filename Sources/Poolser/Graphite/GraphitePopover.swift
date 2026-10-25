import SwiftUI

/// What the Graphite popover shows. Kept separate from `UniswapService` so the view can be
/// previewed with fixed data.
struct PortfolioSnapshot {
    var walletAddress: String
    var positions: [Position]
    /// USD fees earned per day, oldest first and ending today; nil until daily history exists.
    var dailyFeesUSD: [Double]?
    /// The same per position, keyed by `Position.id`.
    var positionDailyFeesUSD: [String: [Double]] = [:]
    var lastUpdated: Date?
    var isLoading = false

    var totalValueUSD: Double { positions.compactMap(\.positionUSD).reduce(0, +) }
    var unclaimedFeesUSD: Double { positions.compactMap(\.usd).reduce(0, +) }
    var chainCount: Int { Set(positions.map(\.chainID)).count }
    var attentionCount: Int { positions.filter { PositionPresentation($0).status.needsAttention }.count }
}

struct GraphitePopoverActions {
    var refresh: (() -> Void)?
    var settings: (() -> Void)?
    var logs: (() -> Void)?
    var quit: (() -> Void)?
    var open: ((Position) -> Void)?
    var collect: ((Position) -> Void)?
}

struct GraphitePopover: View {
    let snapshot: PortfolioSnapshot
    var actions = GraphitePopoverActions()

    enum Filter { case all, needsAttention }

    enum Sort: String, CaseIterable, Identifiable {
        case fees = "Fees", value = "Value", status = "Status"
        var id: Self { self }
    }

    @State private var filter: Filter = .all
    @State private var sort: Sort = .fees
    @State private var chartDays = 14
    @State private var listContentHeight: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    private var palette: GraphitePalette { .current(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            summaryCard
                .padding(.horizontal, 12)
            if snapshot.positions.isEmpty {
                Text(snapshot.isLoading ? "Fetching positions…" : "No active positions found")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            } else {
                chips
                positionList
            }
            footer
        }
        .frame(width: 420)
        .background(palette.popover)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(size: 22)
            Text("Poolser")
                .font(.headline)
                .foregroundStyle(palette.primaryText)
            Text(shortWallet)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(palette.control))
            Spacer()
            iconButton("arrow.clockwise", label: "Refresh", action: actions.refresh, busy: snapshot.isLoading)
            iconButton("slider.horizontal.3", label: "Settings", action: actions.settings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var shortWallet: String {
        let address = snapshot.walletAddress
        guard address.count > 12 else { return address.isEmpty ? "no wallet" : address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }

    private func iconButton(_ symbol: String, label: String, action: (() -> Void)?, busy: Bool = false) -> some View {
        Button { action?() } label: {
            Group {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol).font(.callout.weight(.medium))
                }
            }
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.secondaryText)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unclaimed fees")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                    Text(formatUSD(snapshot.unclaimedFeesUSD))
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.primaryText)
                    if let today = snapshot.dailyFeesUSD?.last {
                        Text("+\(formatUSD(today)) today")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.fees)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total value")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                    Text(formatUSD(snapshot.totalValueUSD))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.primaryText)
                    Text(countsLabel)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.top, 2)
            }
            if let daily = snapshot.dailyFeesUSD, !daily.isEmpty {
                FeeHistoryChart(values: daily, days: $chartDays)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.cardLine, lineWidth: 1))
    }

    private var countsLabel: String {
        let positions = snapshot.positions.count
        let chains = snapshot.chainCount
        return "\(positions) position\(positions == 1 ? "" : "s") · \(chains) chain\(chains == 1 ? "" : "s")"
    }

    // MARK: - Filters

    private var chips: some View {
        HStack(spacing: 6) {
            chip("All \(snapshot.positions.count)", selected: filter == .all) { filter = .all }
            let attention = snapshot.attentionCount
            if attention > 0 || filter == .needsAttention {
                chip("Needs attention \(attention)", selected: filter == .needsAttention, tint: palette.outOfRange) {
                    filter = filter == .needsAttention ? .all : .needsAttention
                }
            }
            Spacer()
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text("Sort: \(sort.rawValue)")
            }
            .menuStyle(.button)
            .buttonStyle(GraphiteChipButtonStyle(
                foreground: palette.secondaryText, background: palette.card, border: palette.cardLine
            ))
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func chip(
        _ title: String,
        selected: Bool,
        tint: GraphitePalette.StatusColors? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let foreground: Color
        let background: Color
        let border: Color
        if let tint {
            foreground = selected ? palette.onStatus : tint.tint
            background = selected ? tint.tint : tint.background
            border = selected ? tint.tint : tint.bandEdge
        } else {
            foreground = selected ? palette.onStrong : palette.secondaryText
            background = selected ? palette.strong : palette.card
            border = selected ? palette.strong : palette.cardLine
        }
        return Button(title, action: action)
            .buttonStyle(GraphiteChipButtonStyle(foreground: foreground, background: background, border: border))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Positions

    private var visiblePositions: [Position] {
        let filtered = filter == .all
            ? snapshot.positions
            : snapshot.positions.filter { PositionPresentation($0).status.needsAttention }
        switch sort {
        case .fees:   return filtered.sorted { ($0.usd ?? 0) > ($1.usd ?? 0) }
        case .value:  return filtered.sorted { ($0.positionUSD ?? 0) > ($1.positionUSD ?? 0) }
        case .status: return filtered.sorted { statusRank($0) < statusRank($1) }
        }
    }

    private func statusRank(_ pos: Position) -> Int {
        switch PositionPresentation(pos).status {
        case .outOfRange: return 0
        case .unknown: return 1
        case .nearMin, .nearMax: return 2
        case .inRange: return 3
        case .fullRange: return 4
        }
    }

    private var positionList: some View {
        let positions = visiblePositions
        return ScrollView {
            VStack(spacing: 8) {
                ForEach(positions) { pos in
                    GraphitePositionCard(
                        position: pos,
                        recentDailyFees: snapshot.positionDailyFeesUSD[pos.id],
                        onOpen: actions.open.map { open in { open(pos) } },
                        onCollect: actions.collect.map { collect in { collect(pos) } }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listContentHeight = $0 }
        }
        // As tall as the cards up to a cap, so short lists don't leave an empty band.
        .frame(height: min(listContentHeight ?? CGFloat(positions.count) * 150 + 12, 560))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(snapshot.isLoading ? palette.nearEdge.tint : palette.fees)
                .frame(width: 6, height: 6)
            if let updated = snapshot.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Updated \(updated.formatted(.relative(presentation: .named, unitsStyle: .wide)))")
                        .id(context.date)
                }
            } else {
                Text(snapshot.isLoading ? "Updating…" : "Not updated yet")
            }
            Spacer()
            Button("Logs") { actions.logs?() }
            Button("Quit") { actions.quit?() }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }
}

// MARK: - Fee history chart

struct FeeHistoryChart: View {
    let values: [Double]
    @Binding var days: Int

    @Environment(\.colorScheme) private var colorScheme

    private var periods: [Int] {
        let options = [7, 14, 30].filter { $0 <= values.count }
        return options.isEmpty ? [values.count] : options
    }

    var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        let shown = Array(values.suffix(min(days, values.count)))
        let peak = shown.max() ?? 0
        VStack(spacing: 6) {
            HStack {
                Spacer()
                Text(formatUSD(shown.last ?? 0))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(palette.onBarToday)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(palette.barToday))
            }
            HStack(alignment: .bottom, spacing: shown.count > 20 ? 2 : 4) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, value in
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                        .fill(index == shown.count - 1 ? palette.barToday : palette.bar)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(2, peak > 0 ? 48 * value / peak : 2))
                }
            }
            .frame(height: 48, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fees per day, last \(shown.count) days")
            .accessibilityValue("Today \(formatUSD(shown.last ?? 0))")
            HStack {
                Text(startDate(daysBack: shown.count - 1), format: .dateTime.month(.abbreviated).day())
                Spacer()
                if periods.count > 1 {
                    Picker("Period", selection: $days) {
                        ForEach(periods, id: \.self) { Text("\($0)D").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.mini)
                    .fixedSize()
                    Spacer()
                }
                Text("Today")
            }
            .font(.caption2)
            .foregroundStyle(palette.secondaryText)
        }
    }

    private func startDate(daysBack: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
    }
}
