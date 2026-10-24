import Foundation

actor PriceService {
    typealias Fetcher = @Sendable (
        _ addresses: [String], _ coingeckoPlatformID: String, _ defiLlamaChainKey: String
    ) async -> [String: Double]

    /// `price == nil` records a token the sources answered for but could not price.
    private struct Entry {
        let price: Double?
        let fetchedAt: Date
    }

    private let ttl: TimeInterval
    private let now: @Sendable () -> Date
    private let fetchRemote: Fetcher
    /// Keyed by "platformID:address": the same address can be a different token on another chain.
    private var cache: [String: Entry] = [:]
    /// Requests still on the wire, so v3, v4 and fee history of one refresh share a single fetch.
    private var inFlight: [String: Task<[String: Double], Never>] = [:]

    /// The default TTL stays below the shortest refresh interval (1 min), so every scheduled
    /// refresh sees fresh prices while repeated manual refreshes and the per-refresh call sites
    /// reuse one fetch.
    init(
        ttl: TimeInterval = 55,
        now: @escaping @Sendable () -> Date = { Date() },
        fetcher: Fetcher? = nil
    ) {
        self.ttl = ttl
        self.now = now
        self.fetchRemote = fetcher ?? { addresses, platformID, chainKey in
            await PriceService.fetchFromNetwork(addresses, coingeckoPlatformID: platformID, defiLlamaChainKey: chainKey)
        }
    }

    /// Returns a map of lowercase address → USD price.
    /// Serves cached prices younger than the TTL and joins requests already in flight; the rest
    /// are fetched from CoinGecko, with missing tokens backfilled from DefiLlama.
    func fetchPrices(
        for addresses: [String],
        coingeckoPlatformID: String,
        defiLlamaChainKey: String
    ) async -> [String: Double] {
        let unique = Set(addresses.map { $0.lowercased() })
        guard !unique.isEmpty else { return [:] }

        let checkedAt = now()
        var result: [String: Double] = [:]
        var pending: [String: Task<[String: Double], Never>] = [:]
        var toFetch: [String] = []
        for address in unique {
            let key = Self.cacheKey(coingeckoPlatformID, address)
            if let entry = cache[key], checkedAt.timeIntervalSince(entry.fetchedAt) < ttl {
                if let price = entry.price { result[address] = price }
            } else if let task = inFlight[key] {
                pending[address] = task
            } else {
                toFetch.append(address)
            }
        }

        if !toFetch.isEmpty {
            let requested = toFetch.sorted()
            let fetch = fetchRemote
            let task = Task {
                let prices = await fetch(requested, coingeckoPlatformID, defiLlamaChainKey)
                self.store(prices, requested: requested, platformID: coingeckoPlatformID)
                return prices
            }
            for address in requested {
                inFlight[Self.cacheKey(coingeckoPlatformID, address)] = task
                pending[address] = task
            }
        }

        for (address, task) in pending {
            if let price = await task.value[address] { result[address] = price }
        }
        return result
    }

    private func store(_ prices: [String: Double], requested: [String], platformID: String) {
        let fetchedAt = now()
        for address in requested {
            let key = Self.cacheKey(platformID, address)
            inFlight[key] = nil
            if let price = prices[address] {
                cache[key] = Entry(price: price, fetchedAt: fetchedAt)
            } else if !prices.isEmpty {
                // The sources answered, so this token simply has no price. An empty answer is
                // more likely an outage or rate limit, which the next refresh should retry.
                cache[key] = Entry(price: nil, fetchedAt: fetchedAt)
            }
        }
    }

    private static func cacheKey(_ platformID: String, _ address: String) -> String {
        "\(platformID):\(address)"
    }

    private static func fetchFromNetwork(
        _ addresses: [String],
        coingeckoPlatformID: String,
        defiLlamaChainKey: String
    ) async -> [String: Double] {
        var result = await coingecko(addresses, platformID: coingeckoPlatformID)
        let missing = addresses.filter { result[$0] == nil }
        if !missing.isEmpty {
            for (k, v) in await defillama(missing, chainKey: defiLlamaChainKey) where result[k] == nil {
                result[k] = v
            }
        }
        return result
    }

    // MARK: - Sources

    private static func coingecko(_ addresses: [String], platformID: String) async -> [String: Double] {
        let qs = addresses.joined(separator: ",")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://api.coingecko.com/api/v3/simple/token_price/\(platformID)"
            + "?contract_addresses=\(qs)&vs_currencies=usd"
        guard let url = URL(string: urlStr) else { return [:] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] ?? [:]
            return json.reduce(into: [:]) { acc, kv in
                if let usd = kv.value["usd"] { acc[kv.key.lowercased()] = usd }
            }
        } catch { return [:] }
    }

    private static func defillama(_ addresses: [String], chainKey: String) async -> [String: Double] {
        let qs = addresses.map { "\(chainKey):\($0)" }.joined(separator: ",")
        guard let url = URL(string: "https://coins.llama.fi/prices/current/\(qs)") else { return [:] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json  = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let coins = json["coins"] as? [String: Any] else { return [:] }
            return coins.reduce(into: [:]) { acc, kv in
                guard let dict  = kv.value as? [String: Any],
                      let price = dict["price"] as? Double,
                      let addr  = kv.key.components(separatedBy: ":").last else { return }
                acc[addr.lowercased()] = price
            }
        } catch { return [:] }
    }
}
