import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// Runs a collect: a dry run from the owner's address, then the browser page that hands the
/// transaction to the user's wallet, then a refresh once it is sent.
@MainActor
final class FeeCollector: ObservableObject {
    enum Status: Equatable {
        case checking(pair: String)
        case waitingForWallet(pair: String)
        case sent(pair: String, transaction: URL?)
        case failed(String)
    }

    @Published private(set) var status: Status?
    /// Called a while after a transaction is sent, so the refresh sees it mined.
    var onSent: (() -> Void)?

    private var server: WalletBridgeServer?
    private var task: Task<Void, Never>?
    private static let refreshDelay: Duration = .seconds(30)

    func collect(_ position: Position, owner: String) {
        task?.cancel()
        server?.stop()
        server = nil
        guard let request = CollectRequest(position: position, owner: owner) else {
            status = .failed("This position cannot be collected from Poolser.")
            return
        }
        guard let chain = SupportedChain.byID(position.chainID),
              let rpcURL = AppSettings.shared.infuraRPCURL(for: chain) else {
            status = .failed("No RPC endpoint for \(request.chainName).")
            return
        }
        status = .checking(pair: request.pairLabel)
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
            self?.openPage(for: request)
        }
    }

    func dismiss() {
        status = nil
    }

    private func openPage(for request: CollectRequest) {
        #if canImport(AppKit)
        let logo = BrandMark.logoPNG(pixels: 128)
        #else
        let logo: Data? = nil
        #endif
        let server: WalletBridgeServer
        do {
            server = try WalletBridgeServer { nonce in CollectPage.html(for: request, nonce: nonce, logoPNG: logo) }
        } catch {
            status = .failed("Could not open the local page: \(error.localizedDescription)")
            return
        }
        self.server = server
        server.start(
            onReady: { [weak self] url in
                Task { @MainActor in
                    #if canImport(AppKit)
                    NSWorkspace.shared.open(url)
                    #endif
                    self?.status = .waitingForWallet(pair: request.pairLabel)
                }
            },
            onEvent: { [weak self] event in
                Task { @MainActor in self?.handle(event, for: request) }
            }
        )
    }

    private func handle(_ event: WalletBridgeServer.Event, for request: CollectRequest) {
        switch event {
        case .sent(let hash):
            LogStore.shared.log("collect #\(request.tokenId): sent \(hash)", level: .info)
            status = .sent(pair: request.pairLabel, transaction: request.explorerTxPrefix.flatMap { URL(string: $0 + hash) })
            server = nil
            task = Task { [weak self] in
                try? await Task.sleep(for: Self.refreshDelay)
                guard !Task.isCancelled else { return }
                self?.onSent?()
            }
        case .failed(let message):
            LogStore.shared.log("collect #\(request.tokenId): \(message)", level: .info)
            status = .failed(message)
        case .timedOut:
            server = nil
            if case .waitingForWallet = status { status = nil }
        }
    }
}
