import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif
import PoolserKit

/// Runs a collect: a dry run from the owner's address, then the browser page that hands the
/// transaction to the user's wallet, then a refresh once it is sent.
@MainActor
final class FeeCollector: ObservableObject {
    struct SentTransaction: Equatable {
        let label: String
        let url: URL?
    }

    /// `subject` is what is collected: a pair, or "3 positions on Ethereum".
    enum Status: Equatable {
        case checking(subject: String)
        case waitingForWallet(subject: String)
        /// The first of two transactions is sent; the page waits for the second.
        case partlySent(subject: String, transactions: [SentTransaction])
        case sent(subject: String, transactions: [SentTransaction])
        case failed(String, transactions: [SentTransaction] = [])
    }

    @Published private(set) var status: Status?
    /// Called a while after a transaction is sent, so the refresh sees it mined.
    var onSent: (() -> Void)?

    private var server: WalletBridgeServer?
    private var task: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    /// What the open page sends, in order, to label the hashes it reports.
    private var pageTransactions: [String] = []
    private var sentTransactions: [SentTransaction] = []
    private let prices = PriceService()
    private static let refreshDelay: Duration = .seconds(30)

    func collect(_ position: Position, owner: String) {
        reset()
        guard let request = CollectRequest(position: position, owner: owner) else {
            status = .failed("This position cannot be collected from Poolser.")
            return
        }
        guard let chain = SupportedChain.byID(position.chainID),
              let rpcURL = AppSettings.shared.infuraRPCURL(for: chain) else {
            status = .failed("No RPC endpoint for \(request.chainName).")
            return
        }
        status = .checking(subject: request.pairLabel)
        task = Task { [weak self] in
            do {
                // The same call the wallet will send, run from the owner's address first, so a
                // transaction that would revert never reaches the wallet.
                _ = try await EthereumClient(rpcURL: rpcURL).ethCall(to: request.to, data: request.data, from: request.owner)
            } catch {
                guard !Task.isCancelled else { return }
                LogStore.shared.log("collect #\(request.tokenId): dry run failed — \(error.localizedDescription)", level: .error)
                self?.status = .failed("The collect would fail: \(error.localizedDescription)")
                return
            }
            guard !Task.isCancelled else { return }
            self?.openPage(
                subject: request.pairLabel, logName: "collect #\(request.tokenId)",
                transactions: [request.versionLabel], explorer: request.explorerTxPrefix
            ) { nonce, logo in
                CollectPage.html(for: request, nonce: nonce, logoPNG: logo)
            }
        }
    }

    /// Collects every collectable position on `chainID` in one transaction per position manager.
    /// The page lets the user leave positions out and asks for the transactions again.
    func collectAll(on chainID: String, positions: [Position], owner: String) {
        reset()
        guard let batch = CollectBatch(chainID: chainID, positions: positions, owner: owner) else {
            status = .failed("Nothing to collect on this chain.")
            return
        }
        guard let rpcURL = AppSettings.shared.infuraRPCURL(for: batch.chain) else {
            status = .failed("No RPC endpoint for \(batch.chain.displayName).")
            return
        }
        let checker = CollectBatchChecker(client: EthereumClient(rpcURL: rpcURL))
        let logName = "collect all on \(batch.chain.displayName)"
        status = .checking(subject: batch.subject)
        let prices = prices
        task = Task { [weak self] in
            async let nativeUSD = Self.nativeTokenUSD(on: batch.chain, positions: positions, prices: prices)
            let check = await checker.check(batch, ids: Set(batch.items.map(\.id)))
            guard !Task.isCancelled, let self else { return }
            for (id, reason) in check.failing {
                LogStore.shared.log("\(logName): \(id) would fail — \(reason)", level: .error)
            }
            if let error = check.error {
                LogStore.shared.log("\(logName): \(error)", level: .error)
                status = .failed(error)
                return
            }
            guard !check.transactions.isEmpty else {
                let names = batch.items.filter { check.failing[$0.id] != nil }.map { "\($0.pairLabel) #\($0.tokenId)" }
                status = .failed("The collect would fail for \(names.joined(separator: ", ")).")
                return
            }
            let usd = await nativeUSD
            openPage(
                subject: batch.subject, logName: logName,
                transactions: check.transactions.map(\.versionLabel),
                explorer: CollectRequest.explorerTxPrefix(chainID: batch.chain.id),
                build: { [weak self] body in await self?.rebuild(batch, checker: checker, body: body, nativeUSD: usd) }
            ) { nonce, logo in
                BatchCollectPage.html(
                    for: batch, check: check, feeLabel: check.feeLabel(nativeUSD: usd), nonce: nonce, logoPNG: logo
                )
            }
        }
    }

    func dismiss() {
        status = nil
    }

    private func reset() {
        task?.cancel()
        server?.stop()
        server = nil
        pageTransactions = []
        sentTransactions = []
    }

    /// Checks the selection the page sent and answers with its transactions.
    private func rebuild(
        _ batch: CollectBatch, checker: CollectBatchChecker, body: Data, nativeUSD: Double?
    ) async -> Data? {
        guard let ids = BatchCollectPage.selection(fromBuildBody: body) else { return nil }
        let check = await checker.check(batch, ids: ids)
        if let error = check.error {
            LogStore.shared.log("collect all on \(batch.chain.displayName): \(error)", level: .error)
        }
        pageTransactions = check.transactions.map(\.versionLabel)
        return try? JSONSerialization.data(withJSONObject: BatchCollectPage.planObject(check, feeLabel: check.feeLabel(nativeUSD: nativeUSD)))
    }

    /// USD per native token, for the gas estimate: from a position holding the wrapped token,
    /// else from the price sources.
    private nonisolated static func nativeTokenUSD(
        on chain: SupportedChain, positions: [Position], prices: PriceService
    ) async -> Double? {
        let wrapped = chain.wrappedNativeToken.lowercased()
        for pos in positions where pos.chainID == chain.id {
            if pos.token0.lowercased() == wrapped, let price = pos.price0USD { return price }
            if pos.token1.lowercased() == wrapped, let price = pos.price1USD { return price }
        }
        return await prices.fetchPrices(
            for: [wrapped], coingeckoPlatformID: chain.coingeckoPlatformID, defiLlamaChainKey: chain.defiLlamaChainKey
        )[wrapped]
    }

    private func openPage(
        subject: String, logName: String, transactions: [String], explorer: String?,
        build: WalletBridgeServer.BuildHandler? = nil,
        page: @escaping (_ nonce: String, _ logo: Data?) -> String
    ) {
        #if canImport(AppKit)
        let logo = BrandMark.logoPNG(pixels: 128)
        #else
        let logo: Data? = nil
        #endif
        let server: WalletBridgeServer
        do {
            server = try WalletBridgeServer(page: { nonce in page(nonce, logo) }, build: build)
        } catch {
            status = .failed("Could not open the local page: \(error.localizedDescription)")
            return
        }
        self.server = server
        pageTransactions = transactions
        server.start(
            onReady: { [weak self] url in
                Task { @MainActor in
                    #if canImport(AppKit)
                    NSWorkspace.shared.open(url)
                    #endif
                    self?.status = .waitingForWallet(subject: subject)
                }
            },
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event, subject: subject, logName: logName, explorer: explorer) }
            }
        )
    }

    private func handle(_ event: WalletBridgeServer.Event, subject: String, logName: String, explorer: String?) {
        switch event {
        case .sent(let hashes), .partlySent(let hashes):
            LogStore.shared.log("\(logName): sent \(hashes.isEmpty ? "as a wallet batch" : hashes.joined(separator: ", "))", level: .info)
            let partial = event == .partlySent(hashes: hashes)
            sentTransactions = zip(hashes, labels(for: hashes, partial: partial)).map { hash, label in
                SentTransaction(label: label, url: explorer.flatMap { URL(string: $0 + hash) })
            }
            if !partial {
                status = .sent(subject: subject, transactions: sentTransactions)
                server = nil
            } else {
                status = .partlySent(subject: subject, transactions: sentTransactions)
            }
            refreshTask?.cancel()
            refreshTask = Task { [weak self] in
                try? await Task.sleep(for: Self.refreshDelay)
                guard !Task.isCancelled else { return }
                self?.onSent?()
            }
        case .failed(let message):
            LogStore.shared.log("\(logName): \(message)", level: .info)
            status = .failed(message, transactions: sentTransactions)
        case .timedOut:
            server = nil
            if case .waitingForWallet = status { status = nil }
        }
    }

    /// "View v3 transaction" when the page sends one transaction per position manager and the
    /// hashes match them; one wallet batch carries both in a single transaction.
    private func labels(for hashes: [String], partial: Bool) -> [String] {
        let named = pageTransactions.count > 1 && (partial || hashes.count == pageTransactions.count)
        return hashes.indices.map { index in
            if named, pageTransactions.indices.contains(index) { return "View \(pageTransactions[index]) transaction" }
            return hashes.count > 1 ? "View transaction \(index + 1)" : "View transaction"
        }
    }
}
