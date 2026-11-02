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

/// The All Wallets summary: the total across wallets, each wallet's share of it, and the fees.
/// The card fills with water to the pool level, as a single wallet's summary does, on a gradient
/// that sets the page apart from a single wallet's white card.
public struct AllWalletsSummaryCard: View {
    let overview: WalletOverview
    /// The wallet under the pointer here or in the list, by `SavedWallet.id`.
    @Binding var highlighted: String?

    public init(overview: WalletOverview, highlighted: Binding<String?>) {
        self.overview = overview
        self._highlighted = highlighted
    }

    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Total value · all wallets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 8)
                Text(countsLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }
            Text(formatUSD(overview.totalValueUSD))
                .font(PoolTypography.amount(32, relativeTo: .largeTitle))
                .fontDesign(.rounded)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
            if !overview.barEntries.isEmpty {
                WalletShareBar(entries: overview.barEntries, highlighted: $highlighted)
                    .padding(.top, 12)
            }
            HStack(alignment: .bottom, spacing: 18) {
                stat("Current fees", formatUSD(overview.unclaimedFeesUSD), eyes: true)
                if let summary = overview.feeSummary {
                    stat("Claimed", summary.isSyncing ? "Syncing…" : formatUSD(summary.claimedUSD))
                    Spacer(minLength: 0)
                    // Until the history scan catches up the claimed part is incomplete, so no total yet.
                    stat("All-time fees", summary.isSyncing ? "–" : formatUSD(summary.allTimeUSD), alignment: .trailing)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 22)
            .help(feesHelp)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background {
            ZStack {
                Self.gradient(colorScheme)
                if let level = poolLevel {
                    PoolWater(level: level, color: .white)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .shadow(color: Color(red: 0.12, green: 0.27, blue: 0.47).opacity(colorScheme == .dark ? 0 : 0.18), radius: 9, y: 4)
    }

    /// The logo's green and blue, deepened so white text reads on every part of it.
    static func gradient(_ scheme: ColorScheme) -> LinearGradient {
        let stops: [Color] = scheme == .dark
            ? [Color(red: 0.08, green: 0.31, blue: 0.29), Color(red: 0.10, green: 0.25, blue: 0.38)]
            : [Color(red: 0.12, green: 0.43, blue: 0.36), Color(red: 0.16, green: 0.35, blue: 0.52)]
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// All-time fees over the current value, as on a single wallet's summary. Nil while the
    /// claimed history is incomplete, since a partial total would show the pool too low.
    private var poolLevel: Double? {
        guard let summary = overview.feeSummary, !summary.isSyncing else { return nil }
        return summary.returnOnAssets
    }

    private var countsLabel: String {
        let positions = overview.positionCount
        let chains = overview.chainCount
        return "\(positions) position\(positions == 1 ? "" : "s") · \(chains) chain\(chains == 1 ? "" : "s")"
    }

    private var feesHelp: String {
        """
        Current fees are waiting to be collected. Claimed fees come from the v3 Collect history, \
        valued at current prices; v4 claimed fees are not tracked. The card fills to the share of \
        the total value already earned back in fees.
        """
    }

    private func stat(_ label: String, _ value: String, eyes: Bool = false, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 5) {
                if eyes { PoolEyes() }
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.85))
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Each wallet's part of the total value as one segmented bar. Pointing at a segment, or tapping
/// it where there is no pointer, names the wallet in a tooltip; the wallet's group in the list
/// lights up with it.
struct WalletShareBar: View {
    let entries: [WalletOverview.Entry]
    @Binding var highlighted: String?

    @Environment(\.colorScheme) private var colorScheme
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
            .animation(.easeOut(duration: 0.15), value: highlighted)
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
                    isDimmed: highlighted != nil && highlighted != entry.id,
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
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}

/// One wallet: a header with its totals above a block of its positions.
struct WalletGroup: View {
    let entry: WalletOverview.Entry
    let isHighlighted: Bool
    let isDimmed: Bool
    let actions: WalletOverviewActions

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = GraphitePalette.current(colorScheme)
        let color = palette.walletColor(entry.colorIndex)
        VStack(alignment: .leading, spacing: 6) {
            header(palette, color: color)
            VStack(spacing: 0) {
                rows(palette)
                footer(palette)
            }
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.card))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isHighlighted ? color : palette.cardLine, lineWidth: 1)
            )
            .shadow(color: .black.opacity(isHighlighted && colorScheme == .light ? 0.08 : 0), radius: 8, y: 3)
        }
        .opacity(isDimmed ? 0.55 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.wallet.displayName)
    }

    private func header(_ palette: GraphitePalette, color: Color) -> some View {
        Button { actions.openWallet(entry.wallet) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 13)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(entry.wallet.displayName)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                if entry.wallet.name != nil {
                    Text(WalletAddress.short(entry.wallet.address))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer(minLength: 8)
                if entry.positions != nil {
                    Text("+\(formatUSD(entry.unclaimedFeesUSD))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.fees)
                    Text(formatUSD(entry.valueUSD))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(palette.primaryText)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(entry.wallet.displayName)")
    }

    @ViewBuilder
    private func rows(_ palette: GraphitePalette) -> some View {
        if let positions = entry.positions {
            if positions.isEmpty {
                Text("No active positions")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ForEach(positions) { position in
                    CompactPositionRow(
                        position: position,
                        onOpen: actions.open.map { open in { open(position) } },
                        onHide: actions.hide.map { hide in { hide(position) } }
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(palette.hairline).frame(height: 1)
                    }
                }
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Loading positions…")
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
    }

    private func footer(_ palette: GraphitePalette) -> some View {
        HStack(spacing: 8) {
            Text(statusLabel)
                .font(.caption.weight(entry.attentionCount > 0 ? .semibold : .regular))
                .foregroundStyle(entry.attentionCount > 0 ? palette.outOfRange.tint : palette.secondaryText)
            Spacer(minLength: 8)
            Button { actions.openWallet(entry.wallet) } label: {
                HStack(spacing: 3) {
                    Text("Open wallet")
                    Image(systemName: "chevron.right").imageScale(.small)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.primaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }

    private var statusLabel: String {
        guard let positions = entry.positions, !positions.isEmpty else { return "" }
        if entry.attentionCount > 0 {
            return entry.attentionCount == 1 ? "1 needs attention" : "\(entry.attentionCount) need attention"
        }
        let count = positions.count
        return "\(count) position\(count == 1 ? "" : "s") · all in range"
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
