import SwiftUI

/// What the All Wallets page can do with a wallet or one of its positions.
public struct WalletOverviewActions {
    public var openWallet: (SavedWallet) -> Void
    public var open: ((Position) -> Void)?
    public var hide: ((Position) -> Void)?

    public init(
        openWallet: @escaping (SavedWallet) -> Void,
        open: ((Position) -> Void)? = nil,
        hide: ((Position) -> Void)? = nil
    ) {
        self.openWallet = openWallet
        self.open = open
        self.hide = hide
    }
}

// MARK: - Summary

/// A solid jade-to-petrol overview, distinct from a single wallet's crest and fee pool.
public struct AllWalletsSummaryCard: View {
    let overview: WalletOverview
    @Binding var highlighted: String?

    public init(overview: WalletOverview, highlighted: Binding<String?>) {
        self.overview = overview
        self._highlighted = highlighted
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    public var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("All wallets").font(PoolTypography.heading(18))
                Spacer(minLength: 8)
                Text("\(overview.entries.count) wallets")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Total value").font(.caption).foregroundStyle(.white.opacity(0.85))
                Text(formatUSD(overview.totalValueUSD))
                    .font(PoolTypography.amount(34, relativeTo: .largeTitle))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if !overview.barEntries.isEmpty {
                VStack(spacing: 8) {
                    WalletShareBar(entries: overview.barEntries, highlighted: $highlighted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 4) {
                        ForEach(overview.barEntries) { entry in
                            Button { highlighted = highlighted == entry.id ? nil : entry.id } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(palette.walletColor(entry.colorIndex))
                                        .frame(width: 7, height: 7)
                                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
                                    Text(entry.wallet.displayName).lineLimit(1)
                                    Text(entry.share < 0.01 ? "<1%" : "\(Int((entry.share * 100).rounded()))%")
                                        .monospacedDigit().foregroundStyle(.white.opacity(0.85))
                                }
                                .font(.caption)
                                .padding(.vertical, 5)
                                #if os(iOS)
                                .frame(minHeight: 44)
                                #endif
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.wallet.displayName), \(formatPercent(entry.share)) of value")
                            .accessibilityHint("Highlight wallet")
                            .accessibilityAddTraits(highlighted == entry.id ? .isSelected : [])
                        }
                    }
                }
            }
            Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { feeMetrics }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { feeMetrics }
                    VStack(alignment: .leading, spacing: 12) { feeMetrics }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Self.gradient(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: palette.brandEnd.opacity(colorScheme == .dark ? 0 : 0.16), radius: 9, y: 4)
    }

    @ViewBuilder
    private var feeMetrics: some View {
        AllWalletsMetric(title: "Unclaimed fees", value: formatUSD(overview.unclaimedFeesUSD),
                         explanation: "Fees waiting to be collected across the loaded wallets.")
        if let summary = overview.feeSummary {
            AllWalletsMetric(title: "Claimed", value: summary.isSyncing ? "Syncing…" : formatUSD(summary.claimedUSD),
                             explanation: "Fees already collected from v3 positions across the loaded wallets, valued at current token prices. Claimed v4 fees are not tracked.")
            AllWalletsMetric(title: "APR", value: summary.isSyncing ? "–" : summary.realizedAPR.map(formatPercent) ?? "–",
                             explanation: "Annualized fee return across the loaded wallets: Σ all-time fees ÷ Σ (current position value × years open) × 100. Only positions with known fees, value and an opening date at least one day ago are included. Claimed fees use current token prices. Liquidity changes affect the estimate; this is not a forecast.")
        }
    }

    /// The logo's green and blue, deepened so white text reads on every part of it.
    static func gradient(_ scheme: ColorScheme) -> LinearGradient {
        let stops: [Color] = scheme == .dark
            ? [Color(red: 0.08, green: 0.31, blue: 0.29), Color(red: 0.10, green: 0.25, blue: 0.38)]
            : [Color(red: 0.12, green: 0.43, blue: 0.36), Color(red: 0.16, green: 0.35, blue: 0.52)]
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct AllWalletsMetric: View {
    let title: String
    let value: String
    let explanation: String
    @Environment(\.colorScheme) private var scheme
    @State private var showingExplanation = false

    var body: some View {
        Button { showingExplanation.toggle() } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Text(title)
                    Image(systemName: "info.circle").imageScale(.small)
                }
                .font(.caption2).foregroundStyle(.white.opacity(0.85))
                Text(value).font(PoolTypography.amount(17, relativeTo: .callout))
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint("Show explanation")
        .popover(isPresented: $showingExplanation) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(PoolTypography.heading(16))
                Text(explanation).font(.callout)
            }
            .padding(16).frame(idealWidth: 280, maxWidth: 320, alignment: .leading)
            .foregroundStyle(GraphitePalette.current(scheme).primaryText)
            .background(GraphitePalette.current(scheme).card)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Each wallet's part of the total value as one segmented bar. Pointing at a segment, or tapping
/// it where there is no pointer, names the wallet in a tooltip; the wallet's group in the list
/// lights up with it.
struct WalletShareBar: View {
    let entries: [WalletOverview.Entry]
    @Binding var highlighted: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tipSize: CGSize = .zero

    private static let gap: CGFloat = 2
    private static let inset: CGFloat = 2
    private static let minWidth: CGFloat = 6

    var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        GeometryReader { geo in
            let widths = Self.widths(entries.map(\.share), in: geo.size.width)
            HStack(spacing: Self.gap) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.walletColor(entry.colorIndex))
                        .frame(width: widths[index], height: 10)
                        .opacity(highlighted == nil || highlighted == entry.id ? 1 : 0.35)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside {
                                highlighted = entry.id
                            } else if highlighted == entry.id {
                                highlighted = nil
                            }
                        }
                        .onTapGesture { highlighted = highlighted == entry.id ? nil : entry.id }
                        .accessibilityElement()
                        .accessibilityLabel(entry.wallet.displayName)
                        .accessibilityValue("\(percent(entry.share)) of value, \(formatUSD(entry.valueUSD))")
                }
            }
            .padding(Self.inset)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.92)))
            .overlay(alignment: .topLeading) {
                if let index = entries.firstIndex(where: { $0.id == highlighted }) {
                    let mid = Self.inset + widths[..<index].reduce(0, +) + CGFloat(index) * Self.gap + widths[index] / 2
                    let x = min(max(mid - tipSize.width / 2, 0), max(geo.size.width - tipSize.width, 0))
                    tooltip(entries[index], arrowX: mid - x)
                        .fixedSize()
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { tipSize = $0 }
                        .offset(x: x, y: -tipSize.height - 6)
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: highlighted)
        }
        .frame(height: 14)
        .zIndex(1)
    }

    /// Segment widths proportional to `shares`, none narrower than a fingertip's worth.
    static func widths(_ shares: [Double], in width: CGFloat) -> [CGFloat] {
        let available = max(width - inset * 2 - gap * CGFloat(max(shares.count - 1, 0)), 0)
        let total = shares.reduce(0, +)
        guard total > 0 else { return shares.map { _ in 0 } }
        let raw: [CGFloat] = shares.map { max(available * CGFloat($0 / total), minWidth) }
        let excess = raw.reduce(0, +) - available
        guard excess > 0 else { return raw }
        // Take the room the minimum widths borrowed from the segments above the minimum.
        let flexible = raw.filter { $0 > minWidth }.reduce(0, +)
        return raw.map { $0 > minWidth && flexible > 0 ? $0 - excess * $0 / flexible : $0 }
    }

    private func tooltip(_ entry: WalletOverview.Entry, arrowX: CGFloat) -> some View {
        let palette = GraphitePalette.current(colorScheme)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(palette.walletColor(entry.colorIndex)).frame(width: 8, height: 8)
                Text(entry.wallet.displayName).fontWeight(.semibold)
                Text("\(percent(entry.share)) of value").foregroundStyle(.white.opacity(0.6))
            }
            .font(.caption)
            HStack(spacing: 8) {
                Text(formatUSD(entry.valueUSD))
                Text("+\(formatUSD(entry.unclaimedFeesUSD)) fees").foregroundStyle(Color(red: 0.44, green: 0.87, blue: 0.67))
            }
            .font(.caption.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(red: 0.08, green: 0.09, blue: 0.11)))
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(Color(red: 0.08, green: 0.09, blue: 0.11))
                .frame(width: 8, height: 8)
                .rotationEffect(.degrees(45))
                .offset(x: arrowX - 4, y: 4)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    private func percent(_ share: Double) -> String {
        share < 0.01 ? "<1%" : "\(Int((share * 100).rounded()))%"
    }
}

// MARK: - Wallet list

/// Every wallet as a group of its positions, largest first.
public struct WalletGroupList: View {
    let overview: WalletOverview
    @Binding var highlighted: String?
    let actions: WalletOverviewActions

    public init(overview: WalletOverview, highlighted: Binding<String?>, actions: WalletOverviewActions) {
        self.overview = overview
        self._highlighted = highlighted
        self.actions = actions
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Wallets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text("By value")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(.horizontal, 4)
            ForEach(overview.entries) { entry in
                WalletGroup(
                    entry: entry,
                    isHighlighted: highlighted == entry.id,
                    actions: actions
                )
                .onHover { inside in
                    if inside {
                        highlighted = entry.id
                    } else if highlighted == entry.id {
                        highlighted = nil
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: highlighted)
    }
}

/// Wallet totals stay visible; positions disclose in place without changing the selected wallet.
struct WalletGroup: View {
    let entry: WalletOverview.Entry
    let isHighlighted: Bool
    let actions: WalletOverviewActions

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var positionsExpanded = false

    var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        let color = palette.walletColor(entry.colorIndex)
        VStack(alignment: .leading, spacing: 12) {
            header(palette, color: color)
            if let positions = entry.positions {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) { walletFees(palette); Spacer(minLength: 0); walletStatus(positions, palette: palette) }
                    VStack(alignment: .leading, spacing: 8) { walletFees(palette); walletStatus(positions, palette: palette) }
                }
                if positions.contains(where: { $0.error != nil }) {
                    Label("Position read errors", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(palette.outOfRange.tint)
                }
                Rectangle().fill(palette.hairline).frame(height: 1)
                if !positions.isEmpty {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { positionsExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(positionsExpanded ? "Hide" : "View") \(positions.count) position\(positions.count == 1 ? "" : "s")")
                            Spacer()
                            Image(systemName: positionsExpanded ? "chevron.up" : "chevron.down").imageScale(.small)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                        #if os(iOS)
                        .frame(minHeight: 44)
                        #else
                        .frame(minHeight: 32)
                        #endif
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(positionsExpanded ? "Expanded" : "Collapsed")
                    if positionsExpanded {
                        VStack(spacing: 0) {
                            ForEach(positions) { position in
                                CompactPositionRow(
                                    position: position,
                                    onOpen: actions.open.map { open in { open(position) } },
                                    onHide: actions.hide.map { hide in { hide(position) } }
                                )
                            }
                        }
                    }
                } else {
                    Text("No active positions").font(.caption).foregroundStyle(palette.secondaryText)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading positions…").font(.caption).foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(16)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(isHighlighted ? color : palette.cardLine, lineWidth: 1))
        .shadow(color: color.opacity(isHighlighted && colorScheme == .light ? 0.1 : 0), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.wallet.displayName)
    }

    private func walletFees(_ palette: GraphitePalette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Unclaimed fees").font(.caption2).foregroundStyle(palette.secondaryText)
            Text(formatUSD(entry.unclaimedFeesUSD))
                .font(PoolTypography.amount(17, relativeTo: .callout)).foregroundStyle(palette.fees)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func walletStatus(_ positions: [Position], palette: GraphitePalette) -> some View {
        if entry.attentionCount > 0 {
            Label("\(entry.attentionCount) need\(entry.attentionCount == 1 ? "s" : "") attention", systemImage: "circle.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.outOfRange.tint)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(palette.outOfRange.background, in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        } else if !positions.isEmpty && !positions.contains(where: { $0.error != nil }) {
            Text("All in range").font(.caption2).foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func header(_ palette: GraphitePalette, color: Color) -> some View {
        Button { actions.openWallet(entry.wallet) } label: {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    identity(palette, color: color)
                    walletValue(palette)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        identity(palette, color: color)
                        Spacer(minLength: 4)
                        walletValue(palette)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        identity(palette, color: color)
                        walletValue(palette)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open wallet")
        .help("Open \(entry.wallet.displayName) · \(WalletAddress.short(entry.wallet.address))")
    }

    private func identity(_ palette: GraphitePalette, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay(Capsule().fill(color).frame(width: 5, height: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.wallet.displayName).font(PoolTypography.heading(16)).foregroundStyle(palette.primaryText)
                if let positions = entry.positions {
                    let chains = Set(positions.map(\.chainID)).count
                    Text("\(positions.count) position\(positions.count == 1 ? "" : "s") · \(chains) chain\(chains == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(palette.secondaryText)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func walletValue(_ palette: GraphitePalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if entry.positions != nil {
                Text(formatUSD(entry.valueUSD)).font(PoolTypography.amount(20, relativeTo: .title3))
                    .foregroundStyle(palette.primaryText).lineLimit(1).minimumScaleFactor(0.7)
            }
            Image(systemName: "arrow.up.right").font(.caption2.weight(.semibold))
                .foregroundStyle(palette.secondaryText).accessibilityHidden(true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }
}

/// A position on one line: the pair, where the price sits in the range, value and fees.
struct CompactPositionRow: View {
    let position: Position
    var onOpen: (() -> Void)?
    var onHide: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        Group {
            if let error = position.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(palette.outOfRange.tint)
                    Text("Position #\(position.tokenId): \(error)")
                        .foregroundStyle(palette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .font(.caption)
            } else {
                content(PositionPresentation(position), palette: palette)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .contextMenu {
            if let onOpen {
                Button("Open in Uniswap", action: onOpen)
                Divider()
            }
            Button("Copy Position ID") { Clipboard.copy(position.tokenId) }
            if let onHide {
                Divider()
                Button("Hide Position", action: onHide)
            }
        }
    }

    private func content(_ info: PositionPresentation, palette: GraphitePalette) -> some View {
        let colors = palette.status(info.status)
        return HStack(spacing: 10) {
            TokenPairAvatar(
                base: TokenPairAvatar.Token(
                    symbol: info.baseSymbol,
                    address: info.isInverted ? position.iconAddress1 : position.iconAddress0
                ),
                quote: TokenPairAvatar.Token(
                    symbol: info.quoteSymbol,
                    address: info.isInverted ? position.iconAddress0 : position.iconAddress1
                ),
                chainID: position.chainNumericID,
                chain: SupportedChain.byID(position.chainID)
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(info.pairLabel)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                Text(metaLabel)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                if info.gauge != nil {
                    // In range stays neutral; only a range that needs attention takes a colour.
                    MiniRangeGauge(
                        gauge: info.gauge,
                        colors: colors,
                        track: palette.track,
                        marker: info.status.needsAttention ? colors.tint : palette.secondaryText
                    )
                    .frame(width: 56)
                }
                if info.status.needsAttention {
                    Text(info.status.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(colors.tint)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(info.status.title)
            VStack(alignment: .trailing, spacing: 1) {
                Text(position.poolStateError == nil ? (position.positionUSDLabel ?? "–") : "–")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(palette.primaryText)
                if let fees = position.feesUSDLabel {
                    Text("+\(fees)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.fees)
                }
            }
            .frame(minWidth: 72, alignment: .trailing)
        }
    }

    private var metaLabel: String {
        let chain = SupportedChain.byID(position.chainID)?.displayName ?? position.chainName
        let fee = position.feeFraction == nil ? "dynamic fee" : "\(position.feePct)%"
        return "\(chain) · \(position.versionLabel) · \(fee)"
    }
}

/// The popover's range gauge in miniature: band and current-price marker, no labels. Shared by
/// the All Wallets rows and the widget.
struct MiniRangeGauge: View {
    let gauge: RangeGaugeLayout?
    let colors: GraphitePalette.StatusColors
    let track: Color
    /// The marker colour; the status colour when nil.
    var marker: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(track).frame(height: 3)
                if let gauge {
                    Capsule()
                        .fill(colors.bandFill)
                        .overlay(Capsule().strokeBorder(colors.bandEdge, lineWidth: 1))
                        .frame(width: max((gauge.bandEnd - gauge.bandStart) * width, 4), height: 7)
                        .offset(x: gauge.bandStart * width)
                    Capsule()
                        .fill(marker ?? colors.tint)
                        .frame(width: 3, height: 11)
                        .offset(x: min(max(gauge.marker * width - 1.5, 0), width - 3))
                }
            }
            .frame(height: 11)
        }
        .frame(height: 11)
    }
}

// MARK: - Badge

/// Marks the All Wallets page in the header: a mark per wallet in its colour and how many there are.
public struct AllWalletsBadge: View {
    let colorIndexes: [Int]

    /// `colorIndexes` in saved order.
    public init(colorIndexes: [Int]) {
        self.colorIndexes = colorIndexes
    }

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(colorIndexes.prefix(8), id: \.self) { index in
                    Capsule().fill(palette.walletColor(index)).frame(width: 4, height: 10)
                }
            }
            Text("All \(colorIndexes.count) wallets")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(palette.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(palette.control))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All \(colorIndexes.count) wallets")
    }
}
