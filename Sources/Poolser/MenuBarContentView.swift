import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct MenuBarContentView: View {
    @EnvironmentObject var service: UniswapService
    @ObservedObject private var settings = AppSettings.shared
    @State private var showSettings = false
    @State private var showLogs     = false

    var body: some View {
        if showSettings {
            SettingsView(onDismiss: { showSettings = false })
                .environmentObject(service)
        } else if showLogs {
            LogsView(onDismiss: { showLogs = false })
        } else {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                contentArea
                Divider().opacity(0.4)
                footer
            }
            .frame(width: 420)
        }
    }

    // MARK: - Header

    private var shortWallet: String {
        let addr = settings.walletAddress
        guard !addr.isEmpty else { return "no wallet configured" }
        return addr.hasPrefix("0x") ? addr : "0x\(addr)"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            BrandMark()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Poolser")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("for Uniswap positions")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(shortWallet)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.blue)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(Color.blue.opacity(0.3), lineWidth: 0.7))
            }
            Spacer()
            Button { service.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if service.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(0.65)
                Text("Fetching positions…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Pacing requests to respect RPC rate limits")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                if let err = service.lastError {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                        Text(err)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(err, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy error")
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !service.positions.isEmpty { Divider().opacity(0.4) }
                }
                if service.positions.isEmpty {
                    if service.lastError == nil {
                        Text("No active positions found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(service.positions) { pos in
                                PositionCard(pos: pos)
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxHeight: 340)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
            Spacer()
            Button {
                showLogs = true
            } label: {
                Label("Logs", systemImage: "list.bullet")
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

}

private struct BrandMark: View {
    var body: some View {
        Group {
            if let image = brandImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                    Text("👀")
                        .font(.system(size: 18))
                }
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
    }

    private var brandImage: NSImage? {
        #if SPM_BUILD
        if let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url),
           image.size.width > 0, image.size.height > 0 {
            return image
        }
        #endif
        if let named = NSImage(named: "AppLogo"),
           named.size.width > 0, named.size.height > 0 {
            return named
        }
        if let appIcon = NSApp.applicationIconImage,
           appIcon.size.width > 0, appIcon.size.height > 0 {
            return appIcon
        }
        return nil
    }
}

// MARK: - Position Card

struct PositionCard: View {
    let pos: Position

    var body: some View {
        if let error = pos.error {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text("Position #\(pos.tokenId): \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy error")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 10)
        } else {
            Button { openInUniswap() } label: {
                cardContent.contentShape(Rectangle())
            }
            .buttonStyle(CardButtonStyle())
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(rangeColor)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
                .shadow(color: rangeColor.opacity(0.7), radius: 3)

            VStack(alignment: .leading, spacing: 5) {
                // Row 1: pair + fee tier + version + position value
                HStack(spacing: 5) {
                    Text("\(pos.sym0)/\(pos.sym1)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(pos.feePct)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pos.versionLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                    if let chain = SupportedChain.byID(pos.chainID) {
                        ChainIconView(chain: chain, size: 14)
                    } else {
                        Text(pos.chainLabel)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1), in: Capsule())
                    }
                    Spacer()
                    if let label = pos.positionUSDLabel ?? pos.feesUSDLabel {
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                // Row 2: range bar (hidden for full-range positions)
                if pos.isFullRange {
                    FullRangeTickBar(currentTick: pos.currentTick)
                } else if let tick = pos.currentTick {
                    TickRangeBar(
                        tickLower: pos.tickLower,
                        tickUpper: pos.tickUpper,
                        currentTick: tick,
                        inRange: pos.inRange
                    )
                }
                // Row 3: range badge + distribution
                HStack(spacing: 6) {
                    rangeBadge
                    if let distance = rangeDistanceLabel {
                        Text(distance)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(rangeColor)
                            .lineLimit(1)
                    }
                    let dist = pos.distributionLabel
                    if !dist.isEmpty {
                        Text(dist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                // Row 3b: pool stats (GeckoTerminal)
                if let stats = pos.poolStatsLabel {
                    HStack {
                        Text(stats)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                // Row 4: fees + token ID
                HStack(spacing: 6) {
                    Group {
                        if let feesUSD = pos.feesUSDLabel {
                            Text("fees: \(feesUSD)")
                        } else if let err = pos.feesError {
                            HStack(spacing: 3) {
                                Text("fees: –")
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(err, forType: .string)
                                } label: {
                                    Image(systemName: "exclamationmark.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                .buttonStyle(.plain)
                                .help(err)
                            }
                        } else {
                            Text("fees: \(pos.feesLabel)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer()
                    Text("#\(pos.tokenId)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var rangeBadge: some View {
        Text(pos.rangeLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(rangeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(rangeColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(rangeColor.opacity(0.25), lineWidth: 0.5))
    }

    private var rangeColor: Color {
        if pos.isFullRange { return .blue }
        switch pos.inRange {
        case true:  return .green
        case false: return .orange
        case nil:   return .gray
        }
    }

    private var rangeDistanceLabel: String? {
        guard let tick = pos.currentTick, !pos.isFullRange else { return nil }
        if tick < pos.tickLower {
            return "below \(percentDistance(from: tick, toBoundary: pos.tickLower))"
        }
        if tick > pos.tickUpper {
            return "above \(percentDistance(from: tick, toBoundary: pos.tickUpper))"
        }
        return nil
    }

    private func percentDistance(from tick: Int, toBoundary boundary: Int) -> String {
        let diff = abs(tick - boundary)
        let exponent = Double(diff) * log(1.0001)

        // For very large gaps, percentage becomes unreadable noise; use tick distance instead.
        if exponent > log(1_000) { // >1000x price move
            return "+\(compactInt(diff)) ticks"
        }

        let pct = (exp(exponent) - 1.0) * 100.0
        if pct >= 1000 { return String(format: "%.0f%%", pct) }
        if pct >= 10   { return String(format: "%.1f%%", pct) }
        return String(format: "%.2f%%", pct)
    }

    private func compactInt(_ value: Int) -> String {
        let n = Double(value)
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000).replacingOccurrences(of: ".0M", with: "M") }
        if n >= 1_000 { return String(format: "%.1fk", n / 1_000).replacingOccurrences(of: ".0k", with: "k") }
        return String(value)
    }

    private func openInUniswap() {
        let urlStr: String
        if pos.isV4 {
            urlStr = "https://app.uniswap.org/positions/v4/\(pos.chainNumericID)/\(pos.tokenId)"
        } else {
            urlStr = "https://app.uniswap.org/pools/\(pos.tokenId)?chain=\(pos.chainID)"
        }
        guard let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Card Button Style

private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassCard(cornerRadius: 10)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Glass Card Modifier

extension View {
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.07), radius: 4, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Tick Range Bar

struct TickRangeBar: View {
    let tickLower: Int
    let tickUpper: Int
    let currentTick: Int
    let inRange: Bool?
    @State private var animatedTick: Double

    private var accent: Color {
        switch inRange {
        case true:  return .green
        case false: return .orange
        case nil:   return .gray
        }
    }

    init(tickLower: Int, tickUpper: Int, currentTick: Int, inRange: Bool?) {
        self.tickLower = tickLower
        self.tickUpper = tickUpper
        self.currentTick = currentTick
        self.inRange = inRange
        _animatedTick = State(initialValue: Double(currentTick))
    }

    var body: some View {
        VStack(spacing: 2) {
            Canvas { ctx, size in
                let w = size.width
                let midY = size.height / 2
                let span = Double(tickUpper - tickLower)
                guard span > 0 else { return }

                // Display window: 1.5× the range on each side, so the range
                // occupies the centre third of the bar.
                let dMin = Double(tickLower) - span * 1.5
                let dSpan = span * 4.0

                func px(_ tick: Double) -> Double {
                    (tick - dMin) / dSpan * Double(w)
                }

                let lx = px(Double(tickLower))
                let rx = px(Double(tickUpper))
                let rawNeedleX = px(animatedTick)
                // Clamp needle so it's always visible; a tiny inset keeps it
                // fully inside the canvas even when very far out of range.
                let nx = min(max(rawNeedleX, 2), Double(w) - 2)

                // ── track (full width, subtle) ──────────────────────────────
                ctx.fill(
                    Path(roundedRect: .init(x: 0, y: midY - 1.5, width: Double(w), height: 3),
                         cornerRadius: 1.5),
                    with: .color(.primary.opacity(0.08))
                )

                // ── range fill ──────────────────────────────────────────────
                ctx.fill(
                    Path(roundedRect: .init(x: lx, y: midY - 1.5, width: rx - lx, height: 3),
                         cornerRadius: 1.5),
                    with: .color(accent.opacity(0.28))
                )

                // Distinct out-of-range style: diagonal stripe overlay.
                if inRange == false {
                    var x = lx
                    while x <= rx + 6 {
                        var stripe = Path()
                        stripe.move(to: CGPoint(x: x, y: midY - 4))
                        stripe.addLine(to: CGPoint(x: x + 6, y: midY + 4))
                        ctx.stroke(stripe, with: .color(accent.opacity(0.35)), lineWidth: 0.9)
                        x += 6
                    }
                }

                // ── range boundary ticks (thin, slightly taller than track) ─
                for bx in [lx, rx] {
                    ctx.fill(
                        Path(roundedRect: .init(x: bx - 0.75, y: midY - 5, width: 1.5, height: 10),
                             cornerRadius: 0.75),
                        with: .color(.secondary.opacity(0.4))
                    )
                }

                // ── current-price needle (tallest element, colored) ─────────
                ctx.fill(
                    Path(roundedRect: .init(x: nx - 1.25, y: midY - 7, width: 2.5, height: 14),
                         cornerRadius: 1.25),
                    with: .color(accent)
                )

                // Off-scale direction indicator when current price lies outside visible window.
                if rawNeedleX < 0 {
                    var arrow = Path()
                    arrow.move(to: CGPoint(x: 1, y: midY))
                    arrow.addLine(to: CGPoint(x: 7, y: midY - 4))
                    arrow.addLine(to: CGPoint(x: 7, y: midY + 4))
                    arrow.closeSubpath()
                    ctx.fill(arrow, with: .color(accent.opacity(0.85)))
                } else if rawNeedleX > Double(w) {
                    var arrow = Path()
                    arrow.move(to: CGPoint(x: Double(w) - 1, y: midY))
                    arrow.addLine(to: CGPoint(x: Double(w) - 7, y: midY - 4))
                    arrow.addLine(to: CGPoint(x: Double(w) - 7, y: midY + 4))
                    arrow.closeSubpath()
                    ctx.fill(arrow, with: .color(accent.opacity(0.85)))
                }
            }
            .frame(height: 14)

            // Numeric anchors for quick orientation.
            HStack {
                Text(String(tickLower))
                Spacer()
                Text(String(Int(animatedTick.rounded())))
                    .foregroundStyle(accent)
                Spacer()
                Text(String(tickUpper))
            }
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        .animation(.easeInOut(duration: 0.35), value: animatedTick)
        .onChange(of: currentTick) { _, nextTick in
            withAnimation(.easeInOut(duration: 0.35)) {
                animatedTick = Double(nextTick)
            }
        }
        .help("Range [\(String(tickLower)), \(String(tickUpper))] • current \(String(currentTick))")
    }
}

struct FullRangeTickBar: View {
    let currentTick: Int?

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.blue.opacity(0.18))
                    Capsule()
                        .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                    if currentTick != nil {
                        Capsule()
                            .fill(Color.blue.opacity(0.9))
                            .frame(width: 3, height: 14)
                            .offset(x: w / 2 - 1.5)
                    }
                }
            }
            .frame(height: 14)

            HStack {
                Text("full range")
                Spacer()
                if let tick = currentTick {
                    Text("tick \(tick)")
                }
            }
            .font(.system(size: 9, weight: .regular, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        .help("Full-range position")
    }
}
