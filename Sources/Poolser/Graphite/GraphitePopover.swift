import SwiftUI
import PoolserKit

/// What the Graphite popover shows. Kept separate from `UniswapService` so the view can be
/// previewed with fixed data.
struct PopoverSnapshot {
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
    /// A collect in progress or how it ended.
    var notice: Notice?

    var totalValueUSD: Double { positions.compactMap(\.positionUSD).reduce(0, +) }
    var unclaimedFeesUSD: Double { positions.compactMap(\.usd).reduce(0, +) }
    var chainCount: Int { Set(positions.map(\.chainID)).count }
}

struct Notice: Equatable {
    enum Kind { case progress, success, failure }
    struct Link: Equatable, Hashable {
        let title: String
        let url: URL
    }
    let kind: Kind
    let text: String
    /// One per transaction sent.
    var links: [Link] = []
}

struct GraphitePopoverActions {
    var refresh: (() -> Void)?
    var settings: (() -> Void)?
    var logs: (() -> Void)?
    var quit: (() -> Void)?
    var open: ((Position) -> Void)?
    /// Offered only on positions `CollectRequest.canCollect` accepts.
    var collect: ((Position) -> Void)?
    var hide: ((Position) -> Void)?
    /// Collects every collectable position on a chain, by chain ID.
    var collectAll: ((String) -> Void)?
    var dismissNotice: (() -> Void)?
}

struct GraphitePopover: View {
    let snapshot: PopoverSnapshot
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
            if let notice = snapshot.notice {
                noticeBanner(notice)
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

    private func noticeBanner(_ notice: Notice) -> some View {
        let tint: Color
        let background: Color
        switch notice.kind {
        case .progress: (tint, background) = (palette.secondaryText, palette.control)
        case .success:  (tint, background) = (palette.inRange.tint, palette.inRange.background)
        case .failure:  (tint, background) = (palette.outOfRange.tint, palette.outOfRange.background)
        }
        return HStack(alignment: .top, spacing: 8) {
            Group {
                switch notice.kind {
                case .progress: ProgressView().controlSize(.mini)
                case .success:  Image(systemName: "checkmark.circle.fill")
                case .failure:  Image(systemName: "xmark.octagon.fill")
                }
            }
            .foregroundStyle(tint)
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.text)
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(notice.links, id: \.self) { link in
                    Link(link.title, destination: link.url)
                        .foregroundStyle(tint)
                }
            }
            Spacer(minLength: 0)
            if notice.kind != .progress, let dismiss = actions.dismissNotice {
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.secondaryText)
                    .help("Dismiss")
                    .accessibilityLabel("Dismiss")
            }
        }
        .font(.caption)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(background))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        PoolEyes()
                        Text("Unclaimed fees")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                    }
                    Text(formatUSD(snapshot.unclaimedFeesUSD))
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .fontDesign(.rounded)
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
                        .fontDesign(.rounded)
                        .foregroundStyle(palette.primaryText)
                    Text(countsLabel)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                    collectAllButton
                        .padding(.top, 6)
                }
                .padding(.top, 2)
            }
            if let daily = snapshot.dailyFeesUSD, !daily.isEmpty {
                FeeHistoryChart(values: daily, days: $chartDays)
            }
            if let summary = snapshot.feeSummary, !summary.isSyncing {
                poolStats(summary)
            }
        }
        .padding(14)
        .background {
            ZStack {
                palette.card
                if let level = poolLevel {
                    PoolWater(level: level)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.cardLine, lineWidth: 1))
    }

    /// How full the fee pool is: all-time fees over the current value. Nil while the claimed
    /// history is incomplete, since a partial total would show the pool too low.
    private var poolLevel: Double? {
        guard let summary = snapshot.feeSummary, !summary.isSyncing else { return nil }
        return summary.returnOnAssets
    }

    @ViewBuilder
    private func poolStats(_ summary: WalletFeeSummary) -> some View {
        if summary.claimedUSD > 0 || summary.returnOnAssets != nil || summary.realizedAPR != nil {
            HStack(alignment: .bottom, spacing: 18) {
                if summary.claimedUSD > 0 {
                    poolStat("Claimed", formatUSD(summary.claimedUSD))
                }
                if let feeReturn = summary.returnOnAssets {
                    poolStat("Pool level", formatPercent(feeReturn), unit: "of value")
                }
                Spacer(minLength: 0)
                if let apr = summary.realizedAPR {
                    poolStat("APR since open", formatPercent(apr), tint: palette.fees, alignment: .trailing)
                }
            }
            .accessibilityElement(children: .combine)
            .help("""
            Claimed fees come from the v3 Collect history, valued at current prices; v4 claimed fees \
            are not tracked. Totals include every unhidden position, even when list filters are active.
            Pool level is all-time fees over the current value; the card fills to that level. The APR \
            weighs each position by its value and how long it has been open.
            """)
        }
    }

    private func poolStat(
        _ label: String,
        _ value: String,
        unit: String? = nil,
        tint: Color? = nil,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(tint ?? palette.primaryText)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    /// One button for a single chain, a menu of chains otherwise. Shown once there are two
    /// positions to collect, since one is the card's own Collect.
    @ViewBuilder
    private var collectAllButton: some View {
        let chains = CollectBatch.chains(in: snapshot.positions)
        if let collectAll = actions.collectAll, chains.map(\.count).reduce(0, +) > 1 {
            if chains.count == 1, let chain = chains.first {
                Button("Collect all") { collectAll(chain.chainID) }
                    .buttonStyle(GraphiteStrongButtonStyle())
                    .help("Collect \(chain.label) in one transaction per Uniswap version")
            } else {
                Menu {
                    ForEach(chains) { chain in
                        Button(chain.label) { collectAll(chain.chainID) }
                    }
                } label: {
                    Text("Collect all")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(GraphiteStrongButtonStyle())
                .fixedSize()
                .help("Collect a chain's fees in one transaction per Uniswap version")
            }
        }
    }

    private var countsLabel: String {
        let positions = snapshot.positions.count
        let chains = snapshot.chainCount
        return "\(positions) position\(positions == 1 ? "" : "s") · \(chains) chain\(chains == 1 ? "" : "s")"
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
                        onCollect: CollectRequest.canCollect(pos) ? actions.collect.map { collect in { collect(pos) } } : nil,
                        onHide: actions.hide.map { hide in { hide(pos) } },
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

    /// A short history still gets a week of slots, empty before its first day, so the chart
    /// shows from the first day of recording instead of appearing a day later.
    private var periods: [Int] {
        [7, 14, 30].filter { $0 == 7 || $0 <= values.count }
    }

    private var slots: Int {
        periods.contains(days) ? days : periods.last ?? 7
    }

    /// Value labels fit over a week of bars; longer periods label only their best day and show
    /// the others on hover.
    private var labelsBars: Bool { slots <= 7 }

    @State private var hovered: Int?

    var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        let shown = Array(values.suffix(slots))
        let empty = slots - shown.count
        let peak = shown.max() ?? 0
        let peakIndex = peak > 0 ? shown.lastIndex(of: peak) : nil
        let total = shown.reduce(0, +)
        VStack(spacing: 6) {
            HStack {
                if shown.count > 1 {
                    Text("\(shown.count) days: \(formatUSD(total)) · avg \(formatUSD(total / Double(shown.count)))/day")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                badge(shown: shown, palette: palette)
            }
            HStack(alignment: .bottom, spacing: slots > 20 ? 2 : 4) {
                ForEach(0..<slots, id: \.self) { slot in
                    let index = slot - empty
                    let shape = UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                    VStack(spacing: 2) {
                        if index < 0 {
                            shape.fill(palette.track).frame(height: 3)
                        } else if index == shown.count - 1 {
                            shape
                                .fill(LinearGradient(colors: [palette.brandStart, palette.brandEnd],
                                                     startPoint: .top, endPoint: .bottom))
                                .opacity(hovered == nil || hovered == index ? 1 : 0.6)
                                .frame(height: barHeight(shown[index], peak: peak))
                        } else {
                            // Today's value is in the badge above; past days get their own label
                            // while the slots are wide enough to hold one.
                            if labelsBars {
                                barLabel(shown[index], palette: palette)
                                    .minimumScaleFactor(0.6)
                            }
                            shape
                                .fill(hovered == index ? palette.secondaryText : palette.bar)
                                .frame(height: barHeight(shown[index], peak: peak))
                                .overlay(alignment: .top) {
                                    // Narrower slots label only the best day. It is the tallest
                                    // bar, so its label clears the others; as an overlay it does
                                    // not widen its slot.
                                    if !labelsBars && index == peakIndex {
                                        barLabel(shown[index], palette: palette)
                                            .fixedSize()
                                            .offset(y: -13)
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside, index >= 0 {
                            hovered = index
                        } else if hovered == index {
                            hovered = nil
                        }
                    }
                }
            }
            .frame(height: 62, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fees per day, last \(shown.count) days")
            .accessibilityValue("Today \(formatUSD(shown.last ?? 0)), total \(formatUSD(total))")
            HStack {
                if values.count < 2 {
                    Text("History starts today")
                } else {
                    Text(startDate(daysBack: slots - 1), format: .dateTime.month(.abbreviated).day())
                }
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
        .onChange(of: slots) { hovered = nil }
    }

    private func barLabel(_ value: Double, palette: GraphitePalette) -> some View {
        Text(formatUSD(value))
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(palette.secondaryText)
            .lineLimit(1)
    }

    /// Today's fees, or the hovered day's with its date.
    private func badge(shown: [Double], palette: GraphitePalette) -> some View {
        let index = hovered.flatMap { shown.indices.contains($0) ? $0 : nil } ?? shown.count - 1
        let isToday = index == shown.count - 1
        let value = formatUSD(shown.indices.contains(index) ? shown[index] : 0)
        let date = startDate(daysBack: shown.count - 1 - index).formatted(.dateTime.month(.abbreviated).day())
        return Text(isToday ? value : "\(date) · \(value)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(isToday ? .white : palette.primaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
                if isToday { shape.fill(palette.brand) } else { shape.fill(palette.bar) }
            }
    }

    /// A day that earned anything stays taller than the 3pt empty-slot track, so a small day
    /// next to a large one still reads as data.
    private func barHeight(_ value: Double, peak: Double) -> CGFloat {
        guard value > 0, peak > 0 else { return 2 }
        return max(6, 48 * value / peak)
    }

    private func startDate(daysBack: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
    }
}
