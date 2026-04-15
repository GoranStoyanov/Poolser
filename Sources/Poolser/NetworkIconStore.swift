import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class NetworkIconStore: ObservableObject {
    static let shared = NetworkIconStore()

#if canImport(AppKit)
    @Published private(set) var iconsByChainID: [String: NSImage] = [:]
#endif

    private var platformIconURLByPlatformID: [String: URL] = [:]
    private var didLoadPlatformIndex = false
    private var isLoadingPlatformIndex = false
    private var inFlightChainIDs: Set<String> = []
    private let iconFolderURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let appFolder = base.appendingPathComponent("Poolser", isDirectory: true)
        iconFolderURL = appFolder.appendingPathComponent("NetworkIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconFolderURL, withIntermediateDirectories: true)
        loadPersistedIcons()
        Task { await prefetch(for: SupportedChain.all) }
    }

#if canImport(AppKit)
    func icon(for chain: SupportedChain) -> NSImage? {
        iconsByChainID[chain.id]
    }
#endif

    func prefetch(for chains: [SupportedChain]) async {
        await ensurePlatformIndexLoaded()
        for chain in chains {
            await fetchIconIfNeeded(for: chain)
        }
    }

    private func ensurePlatformIndexLoaded() async {
        if didLoadPlatformIndex || isLoadingPlatformIndex { return }
        isLoadingPlatformIndex = true
        defer { isLoadingPlatformIndex = false }

        guard let url = URL(string: "https://api.coingecko.com/api/v3/asset_platforms") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            var map: [String: URL] = [:]
            for row in rows {
                let imageStrFromObject: String? = {
                    guard let imageObj = row["image"] as? [String: Any] else { return nil }
                    return (imageObj["small"] as? String)
                        ?? (imageObj["thumb"] as? String)
                        ?? (imageObj["large"] as? String)
                }()
                guard let id = row["id"] as? String,
                      let imageStr = (row["image"] as? String)
                        ?? imageStrFromObject
                        ?? (row["image_small"] as? String)
                        ?? (row["image_large"] as? String),
                      let imageURL = URL(string: imageStr) else { continue }
                map[id] = imageURL
            }
            if !map.isEmpty {
                platformIconURLByPlatformID = map
                didLoadPlatformIndex = true
            }
        } catch {
            // Silent fallback: UI uses placeholders when platform metadata cannot be loaded.
        }
    }

    private func fetchIconIfNeeded(for chain: SupportedChain) async {
#if canImport(AppKit)
        if iconsByChainID[chain.id] != nil { return }
#endif
        if inFlightChainIDs.contains(chain.id) { return }

        let fileURL = iconFileURL(forChainID: chain.id)
#if canImport(AppKit)
        if let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) {
            iconsByChainID[chain.id] = image
            return
        }
#endif
        guard let remoteURL = platformIconURLByPlatformID[chain.coingeckoPlatformID]
            ?? hardcodedIconURL(for: chain.coingeckoPlatformID) else { return }

        inFlightChainIDs.insert(chain.id)
        defer { inFlightChainIDs.remove(chain.id) }

        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            guard !data.isEmpty else { return }
            try? data.write(to: fileURL, options: [.atomic])
#if canImport(AppKit)
            if let image = NSImage(data: data) {
                iconsByChainID[chain.id] = image
            }
#endif
        } catch {
            // Silent fallback: UI uses placeholders.
        }
    }

    private func loadPersistedIcons() {
#if canImport(AppKit)
        for chain in SupportedChain.all {
            let fileURL = iconFileURL(forChainID: chain.id)
            guard let data = try? Data(contentsOf: fileURL),
                  let image = NSImage(data: data) else { continue }
            iconsByChainID[chain.id] = image
        }
#endif
    }

    private func iconFileURL(forChainID chainID: String) -> URL {
        iconFolderURL.appendingPathComponent("\(chainID).png", isDirectory: false)
    }

    private func hardcodedIconURL(for platformID: String) -> URL? {
        let raw: String
        switch platformID {
        case "ethereum":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/279/large/ethereum.png"
        case "base":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/131/large/base.png"
        case "arbitrum-one":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/33/large/AO_logomark.png"
        case "optimistic-ethereum":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/41/large/optimism.png"
        case "polygon-pos":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/15/large/polygon_pos.png"
        case "blast":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/192/large/blast.jpeg"
        case "palm":
            raw = "https://icons.llamao.fi/icons/chains/rsz_palm.jpg"
        case "avalanche":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/12/large/avalanche.png"
        case "celo":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/21/large/celo.jpeg"
        case "linea":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/135/large/linea.jpeg"
        case "mantle":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/140/large/mantle.jpeg"
        case "zksync":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/121/large/zksync.jpeg"
        case "binance-smart-chain":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/1/large/bnb_smart_chain.png"
        case "megaeth":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/32266/large/megaeth.jpg"
        case "monad":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/22182/large/monad.png"
        case "unichain":
            raw = "https://coin-images.coingecko.com/asset_platforms/images/22206/large/unichain.png"
        default:
            return nil
        }
        return URL(string: raw)
    }
}
