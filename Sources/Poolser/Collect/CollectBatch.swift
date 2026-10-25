import Foundation

/// Collects the fees of several positions on one chain to their owner, with as few transactions
/// as the contracts allow: every v3 position in one NonfungiblePositionManager `multicall`, every
/// v4 position in one PositionManager `modifyLiquidities`. Poolser never signs: the browser page
/// hands the transactions to the user's wallet.
struct CollectBatch: Equatable {
    /// A position the batch can collect, as the page lists it.
    struct Item: Equatable {
        /// `Position.id`, which the page sends back to select the position.
        let id: String
        let tokenId: UInt64
        let isV4: Bool
        /// The PoolKey's currencies, for v4.
        let currency0: String?
        let currency1: String?
        let pairLabel: String
        let versionLabel: String
        let feesLabel: String
        let feesUSD: Double?
    }

    struct Transaction: Equatable {
        let to: String
        let data: Data
        let versionLabel: String
        /// The `Item.id`s it collects, in calldata order.
        let itemIDs: [String]
    }

    let chain: SupportedChain
    let owner: String
    let items: [Item]

    /// Every position on `chainID` that `CollectRequest.canCollect` accepts; nil when there is none.
    init?(chainID: String, positions: [Position], owner: String) {
        guard CollectRequest.isAddress(owner), let chain = SupportedChain.byID(chainID) else { return nil }
        let items = positions
            .filter { $0.chainID == chainID && CollectRequest.canCollect($0) }
            .compactMap { pos -> Item? in
                guard let tokenId = UInt64(pos.tokenId) else { return nil }
                return Item(
                    id: pos.id, tokenId: tokenId, isV4: pos.isV4, currency0: pos.currency0, currency1: pos.currency1,
                    pairLabel: PositionPresentation(pos).pairLabel, versionLabel: pos.versionLabel,
                    feesLabel: pos.feesUSDLabel ?? pos.feesLabel, feesUSD: pos.usd
                )
            }
        guard !items.isEmpty else { return nil }
        self.chain = chain
        self.owner = owner
        self.items = items
    }

    /// "3 positions on Ethereum".
    var subject: String {
        "\(items.count) position\(items.count == 1 ? "" : "s") on \(chain.displayName)"
    }

    /// The transactions that collect the selected items: at most one per position manager.
    func transactions(for ids: Set<String>, now: Date = Date()) -> [Transaction] {
        let selected = items.filter { ids.contains($0.id) }
        var transactions: [Transaction] = []

        let v3 = selected.filter { !$0.isV4 }
        if let manager = chain.v3NFPM, !v3.isEmpty {
            let collects = v3.map { ABI.callCollectStatic(tokenId: $0.tokenId, recipient: owner) }
            transactions.append(Transaction(
                to: manager,
                // One collect needs no multicall around it.
                data: collects.count == 1 ? collects[0] : ABI.callMulticall(collects),
                versionLabel: "v3", itemIDs: v3.map(\.id)
            ))
        }

        let v4 = selected.filter(\.isV4)
        if let manager = chain.v4PM, !v4.isEmpty {
            var currencies: [String] = []
            for currency in v4.flatMap({ [$0.currency0, $0.currency1] }).compactMap({ $0 })
            where !currencies.contains(where: { $0.lowercased() == currency.lowercased() }) {
                currencies.append(currency)
            }
            transactions.append(Transaction(
                to: manager,
                data: ABI.v4CallCollectFees(
                    tokenIds: v4.map(\.tokenId), currencies: currencies, recipient: owner,
                    deadline: UInt64(now.addingTimeInterval(CollectRequest.deadlineWindow).timeIntervalSince1970)
                ),
                versionLabel: "v4", itemIDs: v4.map(\.id)
            ))
        }
        return transactions
    }

    /// A chain with fees to collect, as the Collect all menu offers it.
    struct ChainSummary: Identifiable, Equatable {
        let chainID: String
        let chainName: String
        let count: Int
        /// Nil when no position on the chain is priced.
        let feesUSD: Double?

        var id: String { chainID }

        /// "Ethereum · 3 positions · $412.00".
        var label: String {
            var parts = [chainName, "\(count) position\(count == 1 ? "" : "s")"]
            if let feesUSD { parts.append(formatUSD(feesUSD)) }
            return parts.joined(separator: " · ")
        }
    }

    /// Chains with something to collect, the most valuable first.
    static func chains(in positions: [Position]) -> [ChainSummary] {
        let collectable = positions.filter { CollectRequest.canCollect($0) }
        return Dictionary(grouping: collectable, by: \.chainID)
            .compactMap { chainID, group -> ChainSummary? in
                guard let first = group.first else { return nil }
                let priced = group.compactMap(\.usd)
                return ChainSummary(
                    chainID: chainID, chainName: first.chainName, count: group.count,
                    feesUSD: priced.isEmpty ? nil : priced.reduce(0, +)
                )
            }
            .sorted { ($0.feesUSD ?? 0, $1.chainName) > ($1.feesUSD ?? 0, $0.chainName) }
    }
}

/// What a selection of a batch would send, checked from the owner's address, and what it costs.
struct CollectBatchCheck: Equatable {
    var transactions: [CollectBatch.Transaction] = []
    /// Gas for all the transactions together.
    var gas = 0
    var gasPriceWei: Int?
    /// Items that make their transaction revert, with the node's reason. They are left out of
    /// `transactions`.
    var failing: [String: String] = [:]
    /// Why the selection cannot be sent: the node could not be asked, or a transaction reverts
    /// although each of its positions passes alone.
    var error: String?

    /// "≈ $0.84" from the native token's USD price; gas units when there is no price.
    func feeLabel(nativeUSD: Double?) -> String? {
        guard error == nil, !transactions.isEmpty, gas > 0 else { return nil }
        guard let gasPriceWei, let nativeUSD else { return "≈ \(gas.formatted(.number.locale(Locale(identifier: "en_US")))) gas" }
        let usd = Double(gas) * Double(gasPriceWei) / 1e18 * nativeUSD
        return usd < 0.01 ? "< $0.01" : "≈ \(formatUSD(usd))"
    }
}

/// Dry runs and gas estimates for a batch against the chain's RPC node.
struct CollectBatchChecker: Sendable {
    /// Runs a transaction from `from` and returns its gas; throws when it would revert.
    var estimateGas: @Sendable (_ to: String, _ data: Data, _ from: String) async throws -> Int
    /// eth_call from `from`; throws when it would revert.
    var dryRun: @Sendable (_ to: String, _ data: Data, _ from: String) async throws -> Void
    var gasPrice: @Sendable () async throws -> Int

    init(
        estimateGas: @escaping @Sendable (String, Data, String) async throws -> Int,
        dryRun: @escaping @Sendable (String, Data, String) async throws -> Void,
        gasPrice: @escaping @Sendable () async throws -> Int
    ) {
        self.estimateGas = estimateGas
        self.dryRun = dryRun
        self.gasPrice = gasPrice
    }

    init(client: EthereumClient) {
        estimateGas = { to, data, from in try await client.ethEstimateGas(to: to, data: data, from: from) }
        dryRun = { to, data, from in _ = try await client.ethCall(to: to, data: data, from: from) }
        gasPrice = { try await client.ethGasPrice() }
    }

    /// Estimates each transaction for `ids`, which executes it from the owner like a dry run.
    /// When one reverts, each of its positions is tried alone so the failing ones can be named;
    /// those are left out and the rest checked again.
    func check(_ batch: CollectBatch, ids: Set<String>, now: Date = Date()) async -> CollectBatchCheck {
        var result = CollectBatchCheck()
        var remaining = ids
        // Each pass either succeeds, stops on an error, or drops at least one failing item.
        while true {
            let transactions = batch.transactions(for: remaining, now: now)
            var gas = 0
            var newlyFailing: [String: String] = [:]
            for transaction in transactions {
                do {
                    gas += try await estimateGas(transaction.to, transaction.data, batch.owner)
                } catch {
                    guard Self.isRevert(error) else {
                        result.error = "Could not check the transaction: \(error.localizedDescription)"
                        return result
                    }
                    let failing = await failingItems(of: transaction, in: batch, now: now)
                    if failing.isEmpty {
                        result.error = "The \(transaction.versionLabel) collect would fail: \(error.localizedDescription)"
                        return result
                    }
                    newlyFailing.merge(failing) { first, _ in first }
                }
            }
            if newlyFailing.isEmpty {
                result.transactions = transactions
                result.gas = gas
                break
            }
            result.failing.merge(newlyFailing) { first, _ in first }
            remaining.subtract(newlyFailing.keys)
        }
        if !result.transactions.isEmpty {
            result.gasPriceWei = try? await gasPrice()
        }
        return result
    }

    private func failingItems(of transaction: CollectBatch.Transaction, in batch: CollectBatch, now: Date) async -> [String: String] {
        var failing: [String: String] = [:]
        for id in transaction.itemIDs {
            guard let single = batch.transactions(for: [id], now: now).first else { continue }
            do {
                try await dryRun(single.to, single.data, batch.owner)
            } catch where Self.isRevert(error) {
                failing[id] = error.localizedDescription
            } catch {
                continue
            }
        }
        return failing
    }

    private static func isRevert(_ error: Error) -> Bool {
        if case EthereumClient.Err.reverted = error { return true }
        return false
    }
}
