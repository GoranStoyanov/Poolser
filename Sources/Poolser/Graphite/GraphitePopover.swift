import SwiftUI
import PoolserKit

/// What the Graphite popover shows. Kept separate from `UniswapService` so the view can be
/// previewed with fixed data.
struct PopoverSnapshot {
    var walletAddress: String
    /// All Wallets and every saved wallet, in swipe order; empty with a single wallet.
    var pages: [WalletPage] = []
    var shownPage: WalletPage?
    /// Every wallet with its totals; set on the All Wallets page only.
    var overview: WalletOverview?
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
    var selectPage: ((WalletPage) -> Void)?
    /// Nil hides Collect all, as on the All Wallets page, whose chains mix wallets.
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
    /// The tallest the popover may be, so the footer stays on screen; nil for no limit.
    var maxHeight: CGFloat?

    /// Narrows the list to positions that need attention, on top of the saved filters.
    @State private var attentionOnly = false
    @State private var listContentHeight: CGFloat?
    /// The popover's height and the position list's share of it, to keep within `maxHeight`.
    @State private var popoverHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0
    /// Horizontal offset of the wallet page while it is swiped or slides to the next wallet.
    @State private var pageOffset: CGFloat = 0
    /// The wallet under the pointer on the All Wallets page, by `SavedWallet.id`.
    @State private var highlightedWallet: String?
    @Environment(\.colorScheme) private var colorScheme
    private var palette: GraphitePalette { .current(colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if snapshot.pages.count > 1 {
                pageDots
            }
            walletPage
                .offset(x: pageOffset)
            footer
        }
        .frame(width: Self.width)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { popoverHeight = $0 }
        .background(palette.popover)
        .background {
            if snapshot.pages.count > 1 {
                WalletSwipeMonitor(onChange: swipeChanged, onEnd: swipeEnded, onStep: { showWallet(step: $0) })
            }
        }
    }

    private static let width: CGFloat = 420

    /// What belongs to the active wallet, which slides when the wallet changes.
    private var walletPage: some View {
        VStack(spacing: 0) {
            if let error = snapshot.lastError {
                errorBanner(error)
            }
            if let notice = snapshot.notice {
                noticeBanner(notice)
            }
            if let overview = snapshot.overview, !snapshot.positions.isEmpty {
                AllWalletsSummaryCard(overview: overview, highlighted: $highlightedWallet)
                    .padding(.horizontal, 12)
                    // Above the list, so the share bar's tooltip is never covered.
                    .zIndex(1)
                overviewList(overview)
            } else {
                if !snapshot.positions.isEmpty {
                    summaryCard
                        .padding(.horizontal, 12)
                }
                content
            }
        }
    }

    // MARK: - Wallet pages

    private var activeIndex: Int? {
        snapshot.pages.firstIndex { $0.id == snapshot.shownPage?.id }
    }

    private func adjacentPage(_ step: Int) -> WalletPage? {
        guard let index = activeIndex else { return nil }
        let target = index + step
        return snapshot.pages.indices.contains(target) ? snapshot.pages[target] : nil
    }

    private func swipeChanged(_ distance: CGFloat) {
        // Past the first or last wallet the page only gives a little.
        let hasTarget = adjacentPage(distance < 0 ? 1 : -1) != nil
        pageOffset = hasTarget ? distance : distance * 0.25
    }

    private func swipeEnded(_ distance: CGFloat) {
        if abs(distance) > 60 {
            showWallet(step: distance < 0 ? 1 : -1)
        } else {
            withAnimation(.snappy) { pageOffset = 0 }
        }
    }

    private func open(_ page: WalletPage) {
        guard let index = snapshot.pages.firstIndex(where: { $0.id == page.id }), let active = activeIndex else { return }
        showWallet(step: index - active)
    }

    /// Slides the page out, switches wallets and slides the next one in from the other side.
    private func showWallet(step: Int) {
        guard let target = adjacentPage(step), let selectPage = actions.selectPage else {
            withAnimation(.snappy) { pageOffset = 0 }
            return
        }
        let width = Self.width
        withAnimation(.easeIn(duration: 0.12)) {
            pageOffset = step > 0 ? -width : width
        } completion: {
            selectPage(target)
            var placement = Transaction()
            placement.disablesAnimations = true
            withTransaction(placement) { pageOffset = step > 0 ? width : -width }
            // Next turn, so the new page is placed off screen before it slides in.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.2)) { pageOffset = 0 }
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(snapshot.pages.enumerated()), id: \.element.id) { target, page in
                let isActive = page.id == snapshot.shownPage?.id
                Button {
                    guard let index = activeIndex, target != index else { return }
                    showWallet(step: target - index)
                } label: {
                    Group {
                        if page == .allWallets {
                            // Like the location arrow on Weather's first page.
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(isActive ? AnyShapeStyle(palette.brand) : AnyShapeStyle(palette.secondaryText.opacity(0.35)))
                        } else {
                            Circle()
                                .fill(isActive ? palette.primaryText : palette.secondaryText.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: 8, height: 8)
                    .padding(2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(page.title)
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(size: 22)
            Text("Poolser")
                .font(PoolTypography.heading(16))
                .foregroundStyle(palette.primaryText)
            walletBadge
            Spacer()
            iconButton("arrow.clockwise", label: "Refresh", action: actions.refresh, busy: snapshot.isLoading)
            iconButton("slider.horizontal.3", label: "Settings", action: actions.settings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var walletLabel: String {
        if let page = snapshot.shownPage { return page.title }
        let address = snapshot.walletAddress
        return address.isEmpty ? "no wallet" : WalletAddress.short(address)
    }

    @ViewBuilder
    private var walletBadge: some View {
        if snapshot.pages.count > 1, actions.selectPage != nil {
            Menu {
                ForEach(Array(snapshot.pages.enumerated()), id: \.element.id) { index, page in
                    Button {
                        guard let active = activeIndex, index != active else { return }
                        showWallet(step: index - active)
                    } label: {
                        let title: String = {
                            guard case .wallet(let wallet) = page else { return page.title }
                            return wallet.name.map { "\($0)  \(WalletAddress.short(wallet.address))" } ?? wallet.address
                        }()
                        if page.id == snapshot.shownPage?.id {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            } label: {
                shownBadge
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Switch wallet")
        } else {
            shownBadge
        }
    }

    @ViewBuilder
    private var shownBadge: some View {
        if snapshot.shownPage == .allWallets {
            AllWalletsBadge(colorIndexes: snapshot.overview?.savedOrder.map(\.colorIndex) ?? [])
        } else {
            walletBadgeLabel
        }
    }

    private var walletBadgeLabel: some View {
        let hasName = snapshot.shownPage?.hasName ?? false
        return Text(walletLabel)
            .font(.system(.caption, design: hasName ? .default : .monospaced).weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(palette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(palette.control))
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
        PortfolioSummaryCard(
            positions: snapshot.positions,
            dailyFees: snapshot.dailyFeesUSD,
            feeSummary: snapshot.feeSummary
        ) {
            collectAllButton
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
        scrollingList(estimate: CGFloat(positions.count) * 260) {
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
        }
    }

    /// Every wallet's positions, grouped by wallet, on the All Wallets page.
    private func overviewList(_ overview: WalletOverview) -> some View {
        scrollingList(estimate: CGFloat(overview.positionCount) * 50 + CGFloat(overview.entries.count) * 80) {
            WalletGroupList(
                overview: overview,
                highlighted: $highlightedWallet,
                actions: WalletOverviewActions(
                    openWallet: { wallet in open(.wallet(wallet)) },
                    open: actions.open,
                    hide: actions.hide
                )
            )
        }
        .padding(.top, 14)
    }

    private func scrollingList<Content: View>(estimate: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listContentHeight = $0 }
        }
        // A definite height lets the menu window resize when the list changes; the estimate
        // only covers the first layout pass, before the content is measured.
        .frame(height: min(listContentHeight ?? estimate + 12, maxListHeight))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        .onDisappear { listHeight = 0 }
    }

    /// 560 points, or less when the rest of the popover leaves less room on screen.
    private var maxListHeight: CGFloat {
        guard let maxHeight else { return 560 }
        let rest = popoverHeight - listHeight
        return min(560, max(160, maxHeight - rest))
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
                .fill(snapshot.isLoading || snapshot.lastError != nil ? palette.nearEdge.tint
                      : snapshot.lastUpdated == nil ? palette.unknown.tint : palette.fees)
                .frame(width: 6, height: 6)
            if let updated = snapshot.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("\(snapshot.lastError == nil ? "Updated" : "Last successful update:") \(updated.formatted(.relative(presentation: .named, unitsStyle: .wide)))")
                        .id(context.date)
                }
            } else {
                Text(snapshot.isLoading ? "Updating…" : snapshot.lastError == nil ? "Not updated yet" : "No successful update yet")
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
