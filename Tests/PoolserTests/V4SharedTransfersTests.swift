import Foundation
import Testing
@testable import PoolserKit

private let walletA = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
private let walletB = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
private let walletC = "0xcccccccccccccccccccccccccccccccccccccccc"
private let transferSig = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
private let head = 1_010

/// Answers eth_blockNumber and eth_getLogs, returning Transfer logs that match the queried topics.
private actor LogNode {
    /// (from, to, tokenId) of every Transfer on the chain.
    let transfers: [(String, String, UInt64)]
    private(set) var logQueries: [[Any]] = []

    init(transfers: [(String, String, UInt64)]) {
        self.transfers = transfers
    }

    func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let result: Any
        switch body["method"] as! String {
        case "eth_blockNumber":
            result = "0x" + String(head, radix: 16)
        case "eth_getLogs":
            let filter = (body["params"] as! [[String: Any]])[0]
            let topics = filter["topics"] as! [Any]
            logQueries.append(topics)
            func matches(_ topic: Any, _ value: String) -> Bool {
                if topic is NSNull { return true }
                if let one = topic as? String { return one == V4OwnershipTracker.padded(value) }
                return (topic as! [String]).contains(V4OwnershipTracker.padded(value))
            }
            result = transfers
                .filter { matches(topics[1], $0.0) && matches(topics[2], $0.1) }
                .map { ["topics": [transferSig, V4OwnershipTracker.padded($0.0), V4OwnershipTracker.padded($0.1),
                                   "0x" + String(repeating: "0", count: 48) + String(format: "%016llx", $0.2)]] }
        default:
            throw URLError(.unsupportedURL)
        }
        let json = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "result": result])
        return (json, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite struct V4SharedTransfersTests {
    private func tracker(_ node: LogNode, defaults: UserDefaults) -> V4OwnershipTracker {
        let eth = EthereumClient(
            rpcURL: URL(string: "https://rpc.test/v3")!,
            limiter: RPCCreditLimiter(creditsPerSecond: 1e9, maxBurstCredits: 1e9)
        ) { try await node.handle($0) }
        return V4OwnershipTracker(
            eth: eth, chain: SupportedChain.byID("ethereum")!, positionManager: "0x1111111111111111111111111111111111111111",
            deployBlock: 100, settings: V4ScanSettings(logChunkSize: 10_000, maxConcurrentLogRequests: 3, maxChunksPerRefresh: 120),
            defaults: defaults
        )
    }

    private func scanned(_ wallets: [String], through block: Int, in defaults: UserDefaults) throws {
        let cache = V4OwnershipCache(
            lastScannedBlock: block, candidateTokenIds: [], ownedTokenIds: [], nextBootstrapFromBlock: nil, bootstrapPassCounter: nil
        )
        for wallet in wallets {
            defaults.set(try JSONEncoder().encode(cache), forKey: "v4OwnershipCache.ethereum.\(wallet.lowercased())")
        }
    }

    @Test func walletsAtTheSameBlockShareOneQueryPerDirection() async throws {
        let defaults = try #require(UserDefaults(suiteName: "V4SharedTransfersTests-\(UUID().uuidString)"))
        try scanned([walletA, walletB], through: 1_000, in: defaults)
        let node = LogNode(transfers: [
            (walletC, walletA, 7),
            (walletB, walletC, 9),
            (walletC, walletB, 11),
        ])

        let shared = try #require(await tracker(node, defaults: defaults).sharedTransfers(wallets: [walletA, walletB]))

        #expect(await node.logQueries.count == 2)
        #expect(shared.currentBlock == head)
        #expect(shared.to[walletA] == [7])
        #expect(shared.from[walletA] == [])
        #expect(shared.to[walletB] == [11])
        #expect(shared.from[walletB] == [9])
    }

    @Test func walletStillBootstrappingScansOnItsOwn() async throws {
        let defaults = try #require(UserDefaults(suiteName: "V4SharedTransfersTests-\(UUID().uuidString)"))
        try scanned([walletA], through: 1_000, in: defaults)
        let node = LogNode(transfers: [])

        let shared = await tracker(node, defaults: defaults).sharedTransfers(wallets: [walletA, walletB])

        #expect(shared == nil)
        #expect(await node.logQueries.isEmpty)
    }
}
