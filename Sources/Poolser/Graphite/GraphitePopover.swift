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
    var lastError: String?
    /// Nil while claimed-fee tracking is off.
    var feeSummary: WalletFeeSummary?

    var totalValueUSD: Double { positions.compactMap(\.positionUSD).reduce(0, +) }
    var unclaimedFeesUSD: Double { positions.compactMap(\.usd).reduce(0, +) }
    var chainCount: Int { Set(positions.map(\.chainID)).count }
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
    @Binding var listOptions: PositionListOptions
    var actions = GraphitePopoverActions()

    /// Narrows the list to positions that need attention, on top of the saved filters.
    @State private var attentionOnly = false
    @State private var chartDays = 14
    @State private var listContentHeight: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    private var palette: GraphitePalette { .current(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = snapshot.lastError {
                errorBanner(error)
            }
            if !snapshot.positions.isEmpty {
                summaryCard
                    .padding(.horizontal, 12)
            }
            content
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

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.nearEdge.tint)
            Text(error)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { Clipboard.copy(error) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryText)
            .help("Copy error")
            .accessibilityLabel("Copy error")
        }
        .font(.caption)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.nearEdge.background))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Unclaimed fees")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)
                    Text(formatUSD(snapshot.unclaimedFeesUSD))
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .foregroundStyle(palette.primaryText)
                    HStack(spacing: 6) {
                        if let today = snapshot.dailyFeesUSD?.last {
                            Text("+\(formatUSD(today)) today")
                                .foregroundStyle(palette.fees)
                        }
                        if let summary = snapshot.feeSummary {
                            // Until the history scan catches up the claimed part is incomplete, so no total yet.
                            Text(summary.isSyncing ? "All-time fees syncing…" : "All-time \(formatUSD(summary.allTimeUSD))")
                                .foregroundStyle(summary.isSyncing || snapshot.dailyFeesUSD != nil
                                                 ? palette.secondaryText : palette.fees)
                        }
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
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
            if let summary = snapshot.feeSummary, !summary.isSyncing, let line = returnLine(summary) {
                Text(line)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .help("""
                    Claimed fees come from the v3 Collect history, valued at current prices; v4 claimed fees \
                    are not tracked. Totals cover every position, including ones hidden by filters.
                    The return is all-time fees over the current value; the APR weighs each position by its \
                    value and how long it has been open.
                    """)
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

    private func returnLine(_ summary: WalletFeeSummary) -> String? {
        var parts: [String] = []
        if summary.claimedUSD > 0 { parts.append("Claimed \(formatUSD(summary.claimedUSD))") }
        if let feeReturn = summary.returnOnAssets { parts.append("earned \(formatPercent(feeReturn)) of value") }
        if let apr = summary.realizedAPR { parts.append("\(formatPercent(apr)) APR since open") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Positions

    @ViewBuilder
    private var content: some View {
        if snapshot.positions.isEmpty {
            if snapshot.isLoading {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Fetching positions…")
                        .font(.callout)
                        .foregroundStyle(palette.primaryText)
                    Text("Pacing requests to respect RPC rate limits")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            } else if snapshot.lastError == nil {
                Text("No active positions found")
                    .font(.callout)
                    .foregroundStyle(palette.secondaryText)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
        } else {
            let filtered = listOptions.apply(to: snapshot.positions)
            let visible = attentionOnly ? filtered.filter(Self.needsAttention) : filtered
            if snapshot.positions.count > 1 || listOptions.isFiltering || attentionOnly {
                chips(filtered: filtered)
            } else {
                Spacer().frame(height: 10)
            }
            if visible.isEmpty {
                noMatchingPositions
            } else {
                positionList(visible)
            }
        }
    }

    private static func needsAttention(_ pos: Position) -> Bool {
        PositionPresentation(pos).status.needsAttention
    }

    private func chips(filtered: [Position]) -> some View {
        HStack(spacing: 6) {
            chip("All \(filtered.count)", selected: !attentionOnly) { attentionOnly = false }
            let attention = filtered.filter(Self.needsAttention).count
            if attention > 0 || attentionOnly {
                chip("Needs attention \(attention)", selected: attentionOnly, tint: palette.outOfRange) {
                    attentionOnly.toggle()
                }
            }
            Spacer()
            filterMenu
            sortMenu
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
        Button(title, action: action)
            .buttonStyle(chipStyle(selected: selected, tint: tint))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chipStyle(selected: Bool, tint: GraphitePalette.StatusColors? = nil) -> GraphiteChipButtonStyle {
        if let tint {
            return GraphiteChipButtonStyle(
                foreground: selected ? palette.onStatus : tint.tint,
                background: selected ? tint.tint : tint.background,
                border: selected ? tint.tint : tint.bandEdge
            )
        }
        return GraphiteChipButtonStyle(
            foreground: selected ? palette.onStrong : palette.secondaryText,
            background: selected ? palette.strong : palette.card,
            border: selected ? palette.strong : palette.cardLine
        )
    }

    /// Chains that have positions, plus the selected one so it can still be seen and cleared
    /// after its positions are gone.
    private var chainChoices: [(id: String, name: String)] {
        var names: [String: String] = [:]
        for pos in snapshot.positions where names[pos.chainID] == nil {
            names[pos.chainID] = SupportedChain.byID(pos.chainID)?.displayName ?? pos.chainName
        }
        if let selected = listOptions.chainID, names[selected] == nil {
            names[selected] = SupportedChain.byID(selected)?.displayName ?? selected
        }
        return names.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    private var filterMenu: some View {
        Menu {
            Toggle("In Range Only", isOn: $listOptions.inRangeOnly)
            Section("Version") {
                Picker("Version", selection: $listOptions.version) {
                    ForEach(PositionVersionFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            let chains = chainChoices
            if chains.count > 1 || listOptions.chainID != nil {
                Section("Chain") {
                    Picker("Chain", selection: $listOptions.chainID) {
                        Text("All Chains").tag(String?.none)
                        ForEach(chains, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            Divider()
            Button("Clear Filters") { listOptions.clearFilters() }
                .disabled(!listOptions.isFiltering)
        } label: {
            Text("Filter")
        }
        .menuStyle(.button)
        .buttonStyle(chipStyle(selected: listOptions.isFiltering))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter positions")
        .accessibilityValue(listOptions.isFiltering ? "On" : "Off")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $listOptions.sort) {
                ForEach(PositionSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text("Sort: \(sortLabel)")
        }
        .menuStyle(.button)
        .buttonStyle(chipStyle(selected: false))
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort positions")
        .accessibilityLabel("Sort by \(listOptions.sort.title)")
    }

    private var sortLabel: String {
        switch listOptions.sort {
        case .value: return "Value"
        case .fees:  return "Fees"
        case .yield: return "Yield"
        case .pair:  return "Pair"
        }
    }

    private var noMatchingPositions: some View {
        VStack(spacing: 8) {
            Text("No positions match the filters")
                .font(.callout)
                .foregroundStyle(palette.secondaryText)
            Button("Clear Filters") {
                listOptions.clearFilters()
                attentionOnly = false
            }
            .controlSize(.small)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private func positionList(_ positions: [Position]) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(positions) { pos in
                    GraphitePositionCard(
                        position: pos,
                        recentDailyFees: snapshot.positionDailyFeesUSD[pos.id],
                        onOpen: actions.open.map { open in { open(pos) } },
                        onCollect: actions.collect.map { collect in { collect(pos) } },
                        onShowOnlyChain: chainFilterAction(for: pos)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listContentHeight = $0 }
        }
        // A definite height lets the menu window resize when the list changes; the estimate
        // only covers the first layout pass, before the cards are measured.
        .frame(height: min(listContentHeight ?? CGFloat(positions.count) * 170 + 12, 560))
    }

    /// Nil when every position is on one chain or the list is already filtered to this one.
    private func chainFilterAction(for pos: Position) -> (() -> Void)? {
        let spansChains = snapshot.chainCount > 1
        guard spansChains, listOptions.chainID != pos.chainID else { return nil }
        return { listOptions.chainID = pos.chainID }
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
