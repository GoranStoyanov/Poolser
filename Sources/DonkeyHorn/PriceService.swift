import Foundation

actor PriceService {
    /// Returns a map of lowercase address → USD price.
    /// Tries CoinGecko first; backfills missing tokens with DefiLlama.
    func fetchPrices(for addresses: [String]) async -> [String: Double] {
        let unique = Array(Set(addresses.map { $0.lowercased() }))
        guard !unique.isEmpty else { return [:] }

        var result = await coingecko(unique)
        let missing = unique.filter { result[$0] == nil }
        if !missing.isEmpty {
            for (k, v) in await defillama(missing) where result[k] == nil {
                result[k] = v
            }
        }
        return result
    }

    // MARK: - Sources

    private func coingecko(_ addresses: [String]) async -> [String: Double] {
        let qs = addresses.joined(separator: ",")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://api.coingecko.com/api/v3/simple/token_price/ethereum"
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

    private func defillama(_ addresses: [String]) async -> [String: Double] {
        let qs = addresses.map { "ethereum:\($0)" }.joined(separator: ",")
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
