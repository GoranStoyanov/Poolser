import Foundation

typealias TokenMetadata = (symbol: String, decimals: Int)

/// Fetches and caches ERC-20 symbol and decimals per token address for one load.
struct TokenMetadataResolver {
    let eth: EthereumClient
    /// Keyed by lowercase address.
    private(set) var cache: [String: TokenMetadata] = [:]

    init(eth: EthereumClient) {
        self.eth = eth
    }

    mutating func resolve(_ addr: String) async -> TokenMetadata {
        let key = addr.lowercased()
        if let hit = cache[key] { return hit }
        var sym = shortenAddr(addr), dec = 18
        if let d = try? await eth.ethCall(to: addr, data: ABI.callSymbol()), !d.isEmpty {
            let s = d.readABIString(); if !s.isEmpty { sym = s }
        }
        if let d = try? await eth.ethCall(to: addr, data: ABI.callDecimals()), !d.isEmpty {
            dec = Int(d.readUInt64(wordAt: 0))
        }
        let meta = (symbol: sym, decimals: dec)
        cache[key] = meta
        return meta
    }
}

private func shortenAddr(_ addr: String) -> String {
    let a = addr.hasPrefix("0x") ? addr : "0x\(addr)"
    guard a.count >= 10 else { return a }
    return "\(a.prefix(6))…\(a.suffix(4))"
}
