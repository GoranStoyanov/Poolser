import Foundation

/// What every saved wallet needs from one chain, read once per refresh instead of once per
/// wallet: the chain ID probe, the v3 and v4 position NFT balances of all wallets in one
/// Multicall, and the v4 Transfer logs of wallets whose scans cover the same blocks.
struct ChainPrefetch {
    /// Set when the chain cannot be used; every wallet fails with it.
    var error: String?
    /// Set when Infura refused the key for this chain, which the caller turns off.
    var accessDenied = false
    /// By lowercased wallet address; missing when the read failed, so the loader reads it itself.
    var v3Balances: [String: UInt64] = [:]
    var v4Balances: [String: UInt64] = [:]
    var v4Transfers: V4SharedTransfers?

    static func load(chain: SupportedChain, wallets: [String], eth: EthereumClient, scanSettings: V4ScanSettings) async -> ChainPrefetch {
        if let failure = await probe(chain: chain, eth: eth) { return failure }

        var prefetch = ChainPrefetch()
        let managers = [chain.supportsV3 ? chain.v3NFPM : nil, chain.supportsV4 ? chain.v4PM : nil]
        let calls = managers.flatMap { manager in
            manager.map { target in wallets.map { ContractCall(target: target, data: ABI.callBalanceOf(owner: $0)) } } ?? []
        }
        var results = await ContractReader(eth: eth, multicall3: chain.multicall3)
            .read(calls, context: "balances \(chain.displayName)")
            .makeIterator()
        for (index, manager) in managers.enumerated() where manager != nil {
            for wallet in wallets {
                guard case .success(let data)? = results.next(), data.count >= 32 else { continue }
                let balance = data.readUInt64(wordAt: 0)
                if index == 0 { prefetch.v3Balances[wallet.lowercased()] = balance }
                else { prefetch.v4Balances[wallet.lowercased()] = balance }
            }
        }

        if let v4PM = chain.v4PM, chain.supportsV4,
           let deployHex = chain.v4DeployBlockHex, let deployBlock = Int(deployHex.dropFirst(2), radix: 16) {
            let holders = wallets.filter { (prefetch.v4Balances[$0.lowercased()] ?? 0) > 0 }
            let tracker = V4OwnershipTracker(
                eth: eth, chain: chain, positionManager: v4PM, deployBlock: deployBlock, settings: scanSettings
            )
            prefetch.v4Transfers = await tracker.sharedTransfers(wallets: holders)
        }
        return prefetch
    }

    /// Nil when the RPC answers for the expected chain.
    static func probe(chain: SupportedChain, eth: EthereumClient) async -> ChainPrefetch? {
        do {
            let probedChainID = try await eth.ethChainId()
            guard probedChainID != chain.chainId else { return nil }
            return ChainPrefetch(
                error: "\(chain.displayName): RPC chain mismatch (expected \(chain.chainId), got \(probedChainID))"
            )
        } catch {
            let msg = error.localizedDescription
            if msg.lowercased().contains("does not have access") ||
                msg.lowercased().contains("not available for project") {
                return ChainPrefetch(
                    error: "\(chain.displayName): Infura access denied for this API key (network auto-disabled)",
                    accessDenied: true
                )
            }
            return ChainPrefetch(error: "\(chain.displayName): RPC unavailable – \(msg)")
        }
    }
}
