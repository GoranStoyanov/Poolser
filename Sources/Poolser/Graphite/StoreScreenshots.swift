#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import PoolserKit

/// Renders the App Store and README screenshots from the app's own views and a demo wallet, so
/// they can be made again for each release:
///
///     POOLSER_SCREENSHOTS=docs/screenshots swift run
///
/// The app writes the images into that folder and quits. Debug builds only.
@MainActor
enum StoreScreenshots {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["POOLSER_SCREENSHOTS"], !path.isEmpty else { return }
        Task {
            do {
                try await render(into: URL(fileURLWithPath: path, isDirectory: true))
            } catch {
                FileHandle.standardError.write(Data("screenshots: \(error)\n".utf8))
            }
            NSApp.terminate(nil)
        }
    }

    private struct Shot {
        let name: String
        /// Nil sizes the image to the view.
        var size: CGSize? = CGSize(width: 1440, height: 900)
        var scheme: ColorScheme = .light
        /// App Store screenshots are flattened JPEGs, since App Store Connect rejects an alpha
        /// channel; README cut-outs stay PNGs with transparent corners.
        var opaque = true
        let view: AnyView
    }

    private enum ShotError: Error {
        case render(String)
        case write(String)
    }

    private static func render(into folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await DemoWallet.prefetchIcons()
        for shot in shots {
            let image = try await capture(shot)
            let url = folder.appendingPathComponent(shot.name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(image, opaque: shot.opaque, to: url)
        }
    }

    private static var shots: [Shot] {
        let snapshot = DemoWallet.snapshot
        var collecting = snapshot
        collecting.notice = Notice(kind: .progress, text: "Confirm the collect for USDC/WETH in your browser wallet.")
        let title = MenuBarTitle.text(valueUSD: snapshot.totalValueUSD, feesUSD: snapshot.unclaimedFeesUSD)
        let flashTitle = MenuBarTitle.text(valueUSD: snapshot.totalValueUSD, feesUSD: snapshot.unclaimedFeesUSD, trend: "🔼")

        return [
            Shot(name: "appstore/1-menu-bar.jpg", view: AnyView(
                StoreCanvas(title: "Uniswap fees, always in view",
                            subtitle: "Every position on every chain, one click away in the menu bar.") {
                    MenuBarScene(menuTitle: title, snapshot: snapshot)
                }
            )),
            Shot(name: "appstore/2-daily-fees.jpg", view: AnyView(
                StoreCanvas(title: "See what you earn each day",
                            subtitle: "Daily fees, all-time return and APR since you opened each position.") {
                    PopoverArt(snapshot: snapshot, scale: 1.5, visibleHeight: 306)
                }
            )),
            Shot(name: "appstore/3-ranges.jpg", view: AnyView(
                StoreCanvas(title: "Know when a range needs you",
                            subtitle: "Each card shows where the price sits, so drifting positions stand out.") {
                    CardsArt(positions: [snapshot.positions[1], snapshot.positions[2]],
                             dailyFees: snapshot.positionDailyFeesUSD)
                }
            )),
            Shot(name: "appstore/4-collect.jpg", view: AnyView(
                StoreCanvas(title: "Collect fees in a click",
                            subtitle: "Claim from the menu bar with the browser wallet you already use.") {
                    PopoverArt(snapshot: collecting, scale: 0.84)
                }
            )),
            Shot(name: "appstore/5-fees-went-up.jpg", view: AnyView(
                StoreCanvas(title: "Fees went up? You'll know",
                            subtitle: "Total value and unclaimed fees sit in the menu bar and blink when fees grow.") {
                    MenuTitleArt(before: title, after: flashTitle)
                }
            )),
            Shot(name: "appstore/6-private.jpg", scheme: .dark, view: AnyView(
                StoreCanvas(title: "Private by design",
                            subtitle: "No account and no tracking. Poolser reads straight from the chain.",
                            dark: true) {
                    PopoverArt(snapshot: snapshot, scale: 0.84)
                }
            )),
            Shot(name: "popover-light.png", size: nil, opaque: false, view: AnyView(
                PopoverCutout(snapshot: snapshot)
            )),
            Shot(name: "popover-dark.png", size: nil, scheme: .dark, opaque: false, view: AnyView(
                PopoverCutout(snapshot: snapshot)
            )),
        ]
    }

    private static func capture(_ shot: Shot) async throws -> CGImage {
        let hosting = NSHostingView(rootView: shot.view.environment(\.colorScheme, shot.scheme))
        var size = shot.size ?? hosting.fittingSize
        var rect = NSRect(origin: .zero, size: size)
        hosting.frame = rect

        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: shot.scheme == .dark ? .darkAqua : .aqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        // Off every screen, but ordered in so SwiftUI lays out, loads logos and runs animations.
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()
        defer { window.close() }

        // Covers the fee pool pouring in and sloshing until it settles.
        try await Task.sleep(for: .seconds(4.5))
        if shot.size == nil {
            // The first fitting size uses the list's height estimate; size again once cards are measured.
            size = hosting.fittingSize
            rect = NSRect(origin: .zero, size: size)
            window.setContentSize(size)
            hosting.frame = rect
            try await Task.sleep(for: .seconds(0.5))
        }

        let scale = 2.0
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw ShotError.render(shot.name) }
        rep.size = size
        hosting.cacheDisplay(in: rect, to: rep)
        guard let image = rep.cgImage else { throw ShotError.render(shot.name) }
        return image
    }

    private static func write(_ image: CGImage, opaque: Bool, to url: URL) throws {
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: alpha.rawValue)
        else { throw ShotError.write(url.lastPathComponent) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flattened = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, (opaque ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil)
        else { throw ShotError.write(url.lastPathComponent) }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        CGImageDestinationAddImage(destination, flattened, opaque ? options : nil)
        guard CGImageDestinationFinalize(destination) else { throw ShotError.write(url.lastPathComponent) }
    }
}

// MARK: - Demo wallet

/// A small, plausible LP wallet: ETH/USDC on Ethereum in range, cbBTC/USDC on Base near its
/// upper bound and a v4 ETH/WBTC position on Optimism that has drifted out of range. Ranges are set
/// around October 2026 prices; token amounts follow the liquidity math for each range.
@MainActor
enum DemoWallet {
    static let address = "0x7a3f9c2e81b54d06a1f3e8b2c97d40e5f1a6c41e"
    static let ethUSD = 2_309.11
    static let btcUSD = 79_815.0

    /// Real contract addresses, so the cards show each token's actual logo.
    private enum Contract {
        static let usdcEthereum = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
        static let wethEthereum = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
        static let usdcBase = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
        static let cbBTCBase = "0xcbb7c0000ab88b473b1f5afd9ef808440eed33bf"
        static let wbtcOptimism = "0x68f180fcce6836688e9084f035309e29bf0a2095"
    }

    static let positions: [Position] = [
        GraphitePreviewData.position(
            chain: "ethereum", chainName: "Ethereum", chainNumericID: 1, tokenId: "1043877",
            token0: Contract.usdcEthereum, token1: Contract.wethEthereum,
            sym0: "USDC", sym1: "WETH", dec0: 6, dec1: 18, feeRaw: 500,
            lower: 1 / 2_620, upper: 1 / 2_050, current: 1 / ethUSD,
            valueUSD: 4_412.60, feesUSD: 38.17, fees0: 19.42, fees1: 0.00812, apr: 16.0,
            amounts: (2_142.73, 0.9830), volume: 112_400_000, tvl: 128_600_000,
            claimedUSD: 212.40, openedDaysAgo: 96
        ),
        GraphitePreviewData.position(
            chain: "base", chainName: "Base", chainNumericID: 8453, tokenId: "3517204",
            token0: Contract.usdcBase, token1: Contract.cbBTCBase,
            sym0: "USDC", sym1: "cbBTC", dec0: 6, dec1: 8, feeRaw: 500,
            lower: 1 / 80_400, upper: 1 / 76_500, current: 1 / btcUSD,
            valueUSD: 3_184.20, feesUSD: 21.64, fees0: 11.08, fees1: 0.0001323, apr: 23.8,
            amounts: (2_713.04, 0.005903), volume: 24_600_000, tvl: 18_900_000,
            claimedUSD: 96.30, openedDaysAgo: 38
        ),
        GraphitePreviewData.position(
            chain: "optimism", chainName: "Optimism", chainNumericID: 10, tokenId: "61254", isV4: true,
            token0: TokenIconStore.nativeAddress, token1: Contract.wbtcOptimism,
            sym0: "ETH", sym1: "WBTC", dec0: 18, dec1: 8, feeRaw: 3_000,
            lower: 1 / 38.9, upper: 1 / 35.2, current: ethUSD / btcUSD,
            valueUSD: 1_041.80, feesUSD: 4.12, fees0: 0.00098, fees1: 0.0000233, apr: 9.4,
            amounts: (0, 0.013053), volume: 310_000, tvl: 3_600_000,
            claimedUSD: 31.80, openedDaysAgo: 63
        ),
    ]

    static var snapshot: PopoverSnapshot {
        PopoverSnapshot(
            walletAddress: address,
            positions: positions,
            dailyFeesUSD: [4.8, 5.6, 5.1, 6.3, 5.9, 4.4, 5.2, 6.8, 7.1, 5.5, 4.9, 6.2, 5.8, 6.6, 7.4,
                           6.1, 5.3, 6.9, 7.8, 6.4, 5.7, 7.2, 6.6, 7.2, 6.2, 6.9, 6.2, 6.9, 7.1, 3.8],
            positionDailyFeesUSD: [
                positions[0].id: [3.6, 3.9, 3.4, 4.1, 3.7, 4.2, 2.3],
                positions[1].id: [2.4, 2.9, 2.6, 2.8, 2.5, 2.9, 1.5],
                positions[2].id: [0.6, 0.4, 0.2, 0, 0, 0, 0],
            ],
            lastUpdated: Date().addingTimeInterval(-90),
            feeSummary: WalletFeeSummary(positions: positions)
        )
    }

    static func prefetchIcons() async {
        for pos in positions {
            await TokenIconStore.shared.fetchIfNeeded(chainID: pos.chainNumericID, address: pos.iconAddress0)
            await TokenIconStore.shared.fetchIfNeeded(chainID: pos.chainNumericID, address: pos.iconAddress1)
        }
        await NetworkIconStore.shared.prefetch(for: positions.compactMap { SupportedChain.byID($0.chainID) })
    }
}

// MARK: - Layout

/// 1440×900 points, rendered at 2× for the App Store's 2880×1800 Mac size: copy on the left,
/// the app on the right, over the logo's green-to-blue gradient.
private struct StoreCanvas<Art: View>: View {
    let title: String
    let subtitle: String
    var dark = false
    @ViewBuilder let art: Art

    var body: some View {
        ZStack(alignment: .leading) {
            Backdrop(dark: dark)
            art
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, 620)
            VStack(alignment: .leading, spacing: 22) {
                BrandMark(size: 64)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                Text(title)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .lineSpacing(-4)
                Text(subtitle)
                    .font(.system(size: 25, weight: .medium, design: .rounded))
                    .lineSpacing(4)
                    .opacity(0.86)
            }
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 500, alignment: .leading)
            .padding(.leading, 100)
        }
        .frame(width: 1440, height: 900)
    }
}

private struct Backdrop: View {
    var dark = false

    var body: some View {
        let palette = GraphitePalette.light
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.04, green: 0.16, blue: 0.12), Color(red: 0.05, green: 0.09, blue: 0.22)]
                    : [palette.brandStart, palette.brandEnd],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(colors: [.white.opacity(dark ? 0.07 : 0.2), .clear],
                           center: UnitPoint(x: 0.2, y: 0.15), startRadius: 0, endRadius: 760)
        }
    }
}

/// The popover with its menu window's rounded corners and shadow.
private struct PopoverArt: View {
    let snapshot: PopoverSnapshot
    var scale: CGFloat = 1
    /// Unscaled points of the popover to show from its top; nil shows all of it.
    var visibleHeight: CGFloat? = nil
    @State private var options = PositionListOptions()

    var body: some View {
        GraphitePopover(snapshot: snapshot, listOptions: $options, actions: DemoActions.all)
            .fixedSize()
            .frame(width: 420, height: visibleHeight, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.08)))
            .scaleEffect(scale)
            .frame(width: 420 * scale, height: visibleHeight.map { $0 * scale })
            .compositingGroup()
            .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
    }
}

/// A menu bar across the top with the popover hanging under Poolser's title.
private struct MenuBarScene: View {
    let menuTitle: String
    let snapshot: PopoverSnapshot

    var body: some View {
        VStack(spacing: 6) {
            MenuBarStrip(title: menuTitle, highlighted: true)
            HStack {
                Spacer()
                PopoverArt(snapshot: snapshot, scale: 0.9)
                    .padding(.trailing, 150)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 1440, height: 900, alignment: .top)
        .padding(.leading, -620)
    }
}

private struct MenuBarStrip: View {
    let title: String
    var highlighted = false

    var body: some View {
        HStack(spacing: 18) {
            Spacer()
            Text(title)
                .padding(.horizontal, 9)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(highlighted ? 0.3 : 0)))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "magnifyingglass")
            Text("Mon 9:41")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(.black.opacity(0.16))
    }
}

/// The menu bar title before and after a refresh that found new fees, zoomed in.
private struct MenuTitleArt: View {
    let before: String
    let after: String

    var body: some View {
        VStack(spacing: 34) {
            pill(before, glow: false)
            Image(systemName: "arrow.down")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            pill(after, glow: true)
        }
    }

    private func pill(_ text: String, glow: Bool) -> some View {
        Text(text)
            .font(.system(size: 46, weight: glow ? .bold : .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.24)))
            .shadow(color: glow ? .white.opacity(0.55) : .clear, radius: 28)
    }
}

/// Position cards on their own, larger than in the popover.
private struct CardsArt: View {
    let positions: [Position]
    let dailyFees: [String: [Double]]
    private let scale: CGFloat = 1.3

    var body: some View {
        VStack(spacing: 18) {
            ForEach(positions) { pos in
                GraphitePositionCard(position: pos, recentDailyFees: dailyFees[pos.id],
                                     onOpen: {}, onCollect: {}, onShowOnlyChain: {})
                    .frame(width: 396)
                    .fixedSize(horizontal: false, vertical: true)
                    .scaleEffect(scale)
                    .frame(width: 396 * scale)
                    .padding(.vertical, 40)
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.22), radius: 30, y: 14)
            }
        }
    }
}

/// The popover alone with transparent corners, for the README.
private struct PopoverCutout: View {
    let snapshot: PopoverSnapshot
    @State private var options = PositionListOptions()

    var body: some View {
        GraphitePopover(snapshot: snapshot, listOptions: $options, actions: DemoActions.all)
            .fixedSize()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.1)))
            .padding(1)
    }
}

/// Every button present, none doing anything.
private enum DemoActions {
    static let all = GraphitePopoverActions(
        refresh: {}, settings: {}, logs: {}, quit: {}, open: { _ in }, collect: { _ in },
        collectAll: { _ in }, dismissNotice: {}
    )
}
#endif
