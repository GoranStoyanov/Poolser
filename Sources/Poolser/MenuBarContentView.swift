import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct MenuBarContentView: View {
    @EnvironmentObject var service: UniswapService
    @EnvironmentObject var collector: FeeCollector
    @ObservedObject private var settings = AppSettings.shared
    @State private var showSettings = false
    @State private var showLogs     = false
    @State private var screenSize: CGSize = .zero

    var body: some View {
        screen
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { screenSize = $0 }
            .background(MenuWindowSizer(contentSize: screenSize))
            .onAppear { collector.onSent = { service.refresh() } }
    }

    @ViewBuilder
    private var screen: some View {
        if showSettings {
            SettingsView(onDismiss: { showSettings = false })
                .environmentObject(service)
        } else if showLogs {
            LogsView(onDismiss: { showLogs = false })
        } else {
            GraphitePopover(
                snapshot: snapshot,
                listOptions: $settings.positionListOptions,
                actions: GraphitePopoverActions(
                    refresh: { service.refresh() },
                    settings: { showSettings = true },
                    logs: { showLogs = true },
                    quit: { NSApp.terminate(nil) },
                    open: { pos in
                        if let url = pos.uniswapURL { NSWorkspace.shared.open(url) }
                    },
                    collect: { pos in collector.collect(pos, owner: owner) },
                    dismissNotice: { collector.dismiss() }
                )
            )
        }
    }

    private var snapshot: PortfolioSnapshot {
        PortfolioSnapshot(
            walletAddress: settings.walletAddress,
            positions: service.positions,
            lastUpdated: service.lastUpdated,
            isLoading: service.isLoading,
            lastError: service.lastError,
            feeSummary: settings.trackClaimedFees && !service.positions.isEmpty
                ? WalletFeeSummary(positions: service.positions)
                : nil,
            notice: collector.status.map(Self.notice)
        )
    }

    private var owner: String {
        let address = settings.walletAddress
        return address.hasPrefix("0x") ? address : "0x" + address
    }

    private static func notice(for status: FeeCollector.Status) -> Notice {
        switch status {
        case .checking(let pair):
            return Notice(kind: .progress, text: "Checking the collect for \(pair)…")
        case .waitingForWallet(let pair):
            return Notice(kind: .progress, text: "Confirm the collect for \(pair) in your browser wallet.")
        case .sent(let pair, let transaction):
            return Notice(kind: .success, text: "Collect for \(pair) sent. Positions refresh shortly.", link: transaction)
        case .failed(let message):
            return Notice(kind: .failure, text: message)
        }
    }
}

/// MenuBarExtra grows its window for taller content but never shrinks it: a shorter screen
/// (Logs after the position list) is centred between empty, transparent bands. This resizes
/// the window to the screen's size, keeping its top edge under the menu bar.
private struct MenuWindowSizer: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let size = contentSize
        // The view is attached to its window after the first update.
        DispatchQueue.main.async {
            guard let window = view.window, size.width > 0, size.height > 0 else { return }
            let current = window.contentRect(forFrameRect: window.frame).size
            guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            frame.origin.x = window.frame.midX - frame.width / 2
            frame.origin.y = window.frame.maxY - frame.height
            window.setFrame(frame, display: true)
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let image = brandImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                    Text("👀")
                        .font(.system(size: size * 0.56))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
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
