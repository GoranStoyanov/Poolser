import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// Token logos from DefiLlama's icon CDN, keyed by chain ID and contract address, so any token
/// it knows needs no index or per-chain list. Address(0) is the chain's native currency.
@MainActor
final class TokenIconStore: ObservableObject {
    static let shared = TokenIconStore()

    static let nativeAddress = "0x0000000000000000000000000000000000000000"

#if canImport(AppKit)
    @Published private(set) var iconsByKey: [String: NSImage] = [:]
#endif

    private var inFlightKeys: Set<String> = []
    /// Failed downloads, so the many views showing a token do not each retry it.
    private var lastFailureByKey: [String: Date] = [:]
    private let failureRetryInterval: TimeInterval = 60 * 60
    /// Tokens the CDN has no logo for get a marker file; it gains logos over time, so look again weekly.
    private let missingRetryInterval: TimeInterval = 7 * 24 * 60 * 60
    private let iconFolderURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        iconFolderURL = base
            .appendingPathComponent("Poolser", isDirectory: true)
            .appendingPathComponent("TokenIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconFolderURL, withIntermediateDirectories: true)
    }

#if canImport(AppKit)
    func icon(chainID: Int, address: String) -> NSImage? {
        iconsByKey[Self.key(chainID: chainID, address: address)]
    }
#endif

    func fetchIfNeeded(chainID: Int, address: String) async {
        let key = Self.key(chainID: chainID, address: address)
#if canImport(AppKit)
        if iconsByKey[key] != nil { return }
#endif
        if inFlightKeys.contains(key) { return }
        if let last = lastFailureByKey[key], Date().timeIntervalSince(last) < failureRetryInterval { return }

        let fileURL = iconFolderURL.appendingPathComponent("\(key).img", isDirectory: false)
        let missingURL = iconFolderURL.appendingPathComponent("\(key).missing", isDirectory: false)
#if canImport(AppKit)
        if let data = try? Data(contentsOf: fileURL), let image = NSImage(data: data) {
            iconsByKey[key] = image
            return
        }
#endif
        if let modified = (try? missingURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(modified) < missingRetryInterval {
            return
        }

        // 128px covers the 26pt avatar on a Retina screen.
        guard let remoteURL = URL(string: "https://token-icons.llamao.fi/icons/tokens/\(chainID)/\(address.lowercased())?h=128&w=128")
        else { return }

        inFlightKeys.insert(key)
        defer { inFlightKeys.remove(key) }

        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 404 {
                FileManager.default.createFile(atPath: missingURL.path, contents: Data())
                return
            }
#if canImport(AppKit)
            guard status == 200, let image = NSImage(data: data) else {
                lastFailureByKey[key] = Date()
                return
            }
            try? data.write(to: fileURL, options: [.atomic])
            try? FileManager.default.removeItem(at: missingURL)
            iconsByKey[key] = image
#endif
        } catch {
            // Silent fallback: the avatar keeps its letter until a later attempt succeeds.
            lastFailureByKey[key] = Date()
        }
    }

    private static func key(chainID: Int, address: String) -> String {
        "\(chainID)-\(address.lowercased())"
    }
}
