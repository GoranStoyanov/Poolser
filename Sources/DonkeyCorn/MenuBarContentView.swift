import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var service: UniswapService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            contentArea
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 420)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Uniswap Positions")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if service.isLoading {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)
            }
            Button { service.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
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
        } else if service.positions.isEmpty {
            Text(service.isLoading ? "Fetching positions…" : "No active positions found")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
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

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings", systemImage: "gear")
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
                        .foregroundStyle(pos.isV4 ? Color.pink : Color.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background((pos.isV4 ? Color.pink : Color.secondary).opacity(0.1), in: Capsule())
                    Spacer()
                    if let label = pos.positionUSDLabel ?? pos.feesUSDLabel {
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                // Row 2: range bar
                if let tick = pos.currentTick {
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
                    let dist = pos.distributionLabel
                    if !dist.isEmpty {
                        Text(dist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
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
        switch pos.inRange {
        case true:  return .green
        case false: return .orange
        case nil:   return .gray
        }
    }

    private func openInUniswap() {
        let urlStr = pos.isV4
            ? "https://app.uniswap.org/positions/v4/1/\(pos.tokenId)"
            : "https://app.uniswap.org/pools/\(pos.tokenId)"
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

    private var accent: Color {
        switch inRange {
        case true:  return .green
        case false: return .orange
        case nil:   return .gray
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let midY = size.height / 2
            let span = Double(tickUpper - tickLower)
            guard span > 0 else { return }

            // Display window: 1.5× the range on each side, so the range
            // occupies the centre third of the bar.
            let dMin = Double(tickLower) - span * 1.5
            let dSpan = span * 4.0

            func px(_ tick: Int) -> Double {
                (Double(tick) - dMin) / dSpan * Double(w)
            }

            let lx = px(tickLower)
            let rx = px(tickUpper)
            // Clamp needle so it's always visible; a tiny inset keeps it
            // fully inside the canvas even when very far out of range.
            let nx = min(max(px(currentTick), 2), Double(w) - 2)

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
        }
        .frame(height: 14)
    }
}
