import Foundation

/// Fetches pool stats (24h volume, fee APR) from GeckoTerminal.
/// Results are cached per pool address for 5 minutes to avoid hammering the free API.
final class PoolStatsService {
    struct Stats {
        let volumeUSD24h: Double
        let feeAPR: Double
    }

    private struct CacheEntry {
        let stats: Stats
        let fetchedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let ttl: TimeInterval = 5 * 60  // 5 minutes

    /// Returns cached stats if fresh, otherwise fetches from GeckoTerminal.
    /// Returns nil if the network is unsupported or the request fails.
    func stats(
        network: String,
        poolAddress: String,
        feePct: Double
    ) async -> Stats? {
        let key = "\(network)/\(poolAddress.lowercased())"
        if let entry = cache[key], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.stats
        }
        guard let stats = await fetch(network: network, poolAddress: poolAddress, feePct: feePct) else {
            return nil
        }
        cache[key] = CacheEntry(stats: stats, fetchedAt: Date())
        return stats
    }

    // MARK: - Private

    private func fetch(
        network: String,
        poolAddress: String,
        feePct: Double
    ) async -> Stats? {
        let urlString = "https://api.geckoterminal.com/api/v2/networks/\(network)/pools/\(poolAddress.lowercased())"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return parse(data: data, feePct: feePct)
        } catch {
            return nil
        }
    }

    private func parse(data: Data, feePct: Double) -> Stats? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = json["data"] as? [String: Any],
            let attrs = dataObj["attributes"] as? [String: Any]
        else { return nil }

        let volumeUSD24h: Double
        if let volDict = attrs["volume_usd"] as? [String: Any],
           let raw = volDict["h24"] {
            volumeUSD24h = toDouble(raw) ?? 0
        } else {
            volumeUSD24h = 0
        }

        let tvl = toDouble(attrs["reserve_in_usd"]) ?? 0
        guard tvl > 0, volumeUSD24h > 0 else { return nil }

        // fee APR = (volume_24h × fee_pct) / TVL × 365 × 100
        let feeAPR = (volumeUSD24h * feePct) / tvl * 365 * 100

        return Stats(volumeUSD24h: volumeUSD24h, feeAPR: feeAPR)
    }

    private func toDouble(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let s as String: return Double(s)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }
}
