import Foundation

public typealias TokenMetadata = (symbol: String, decimals: Int)

/// Caches ERC-20 symbol and decimals per token address for one load. Lookups are batched:
/// `pending(_:)` lists the reads for tokens not cached yet, so a loader can send them together
/// with its other reads, and `store(_:results:)` takes their results.
struct TokenMetadataResolver {
    /// Keyed by lowercase address.
    private(set) var cache: [String: TokenMetadata] = [:]

    struct Pending {
        fileprivate let tokens: [String]
        /// symbol() then decimals() for each token.
        let calls: [ContractCall]
    }

    func pending(_ addrs: some Sequence<String>) -> Pending {
        var seen = Set<String>()
        var tokens: [String] = []
        for addr in addrs {
            let key = addr.lowercased()
            guard cache[key] == nil, seen.insert(key).inserted else { continue }
            tokens.append(addr)
        }
        let calls = tokens.flatMap { token in
            [ContractCall(target: token, data: ABI.callSymbol()),
             ContractCall(target: token, data: ABI.callDecimals())]
        }
        return Pending(tokens: tokens, calls: calls)
    }

    /// `results` are the outcomes of `pending.calls`, in order. A failed or empty read keeps
    /// the default for that field: the shortened address as symbol, 18 decimals.
    mutating func store(_ pending: Pending, results: ArraySlice<Result<Data, Error>>) {
        for (i, token) in pending.tokens.enumerated() {
            let base = results.startIndex + 2 * i
            var sym = shortenAddr(token), dec = 18
            if case .success(let d) = results[base], !d.isEmpty {
                let s = d.readABIString(); if !s.isEmpty { sym = s }
            }
            if case .success(let d) = results[base + 1], !d.isEmpty {
                dec = Int(d.readUInt64(wordAt: 0))
            }
            cache[token.lowercased()] = (symbol: sym, decimals: dec)
        }
    }

    /// Stored metadata, or the defaults for a token that was never looked up.
    func metadata(_ addr: String) -> TokenMetadata {
        cache[addr.lowercased()] ?? (symbol: shortenAddr(addr), decimals: 18)
    }
}

private func shortenAddr(_ addr: String) -> String {
    let a = addr.hasPrefix("0x") ? addr : "0x\(addr)"
    guard a.count >= 10 else { return a }
    return "\(a.prefix(6))…\(a.suffix(4))"
}
