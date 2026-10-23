import Foundation
import Testing
@testable import Poolser

private let collectTopic = "0x40d0efd1a53d60ecbf40971b9daf7dc90178c3aadc7aab1765632738fa8b8f01"
private let chainID = "test"

/// In-memory NFPM log source with scriptable failures.
private final class FakeRPC: @unchecked Sendable {
    struct Collect {
        let block: Int
        let tokenId: String
        let amount0: Int
    }

    private let lock = NSLock()
    private var collects: [Collect]
    private var calls: [(from: Int, to: Int, tokenIds: [String])] = []
    private var hook: (_ from: Int, _ to: Int, _ tokenIds: [String]) async throws -> Void = { _, _, _ in }

    /// Called before each request; throw to fail it.
    var beforeRequest: (_ from: Int, _ to: Int, _ tokenIds: [String]) async throws -> Void {
        get { lock.withLock { hook } }
        set { lock.withLock { hook = newValue } }
    }

    init(_ collects: [Collect]) {
        self.collects = collects
    }

    var requestedRanges: [ClosedRange<Int>] {
        lock.withLock { calls.map { $0.from...$0.to } }
    }

    func fetch(topics: [[String]?], from: Int, to: Int) async throws -> [[String: Any]] {
        let tokenIds = (topics[1] ?? []).compactMap { UInt64($0.dropFirst(2), radix: 16) }.map(String.init)
        lock.withLock { calls.append((from, to, tokenIds)) }
        try await beforeRequest(from, to, tokenIds)
        return lock.withLock {
            collects
                .filter { (from...to).contains($0.block) && tokenIds.contains($0.tokenId) }
                .map(Self.encode)
        }
    }

    private static func encode(_ c: Collect) -> [String: Any] {
        let word = { (v: Int) in String(format: "%064x", v) }
        return [
            "topics": [collectTopic, "0x" + word(Int(c.tokenId)!)],
            "data": "0x" + word(0) + word(c.amount0) + word(0),
            "blockNumber": "0x" + String(c.block, radix: 16),
        ]
    }
}

/// One-shot latch that ignores task cancellation, like an RPC request already on the wire.
private actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

private struct ScanFailure: Error {}

private func position(_ tokenId: String) -> Position {
    var p = Position(
        chainID: chainID, chainName: "Test", chainNumericID: 1, tokenId: tokenId,
        token0: "0x0", token1: "0x1", sym0: "A", sym1: "B", feePct: "0.05", feeRaw: 500,
        fees0: 0, fees1: 0, tickLower: 0, tickUpper: 0, liquidity: 0
    )
    p.dec0 = 0
    p.dec1 = 0
    return p
}

/// Isolated UserDefaults suite and wallet per test, so tests can run in parallel.
private final class Harness {
    let store: UserDefaults
    let suiteName = "PoolserTests.\(UUID().uuidString)"
    let wallet = "0x\(UUID().uuidString)"
    let rpc: FakeRPC
    var positions = [position("1")]
    var chunkSize = 10
    var maxChunks = 100

    init(_ collects: [FakeRPC.Collect] = []) {
        store = UserDefaults(suiteName: suiteName)!
        rpc = FakeRPC(collects)
    }

    deinit {
        store.removePersistentDomain(forName: suiteName)
    }

    var cache: FeeHistoryCache? {
        FeeHistoryService.loadCache(forKey: FeeHistoryService.cacheKey(chainID: chainID, wallet: wallet), store: store)
    }

    @discardableResult
    func scan(currentBlock: Int, deployBlock: Int) async -> FeeHistoryService.Result {
        let rpc = rpc
        return await FeeHistoryService.scan(
            positions: positions,
            deployBlock: deployBlock,
            currentBlock: currentBlock,
            chainID: chainID,
            wallet: wallet,
            chunkSize: chunkSize,
            maxChunks: maxChunks,
            store: store
        ) { topics, from, to in
            try await rpc.fetch(topics: topics, from: from, to: to)
        }
    }

    /// Creates a fully bootstrapped cache with lastSeenBlock == block.
    func seed(at block: Int) async {
        await scan(currentBlock: block, deployBlock: block)
    }
}

@Suite struct FeeHistoryServiceTests {

    @Test func forwardFailureStopsBeforeFailingChunk() async {
        let h = Harness([.init(block: 105, tokenId: "1", amount0: 1), .init(block: 135, tokenId: "1", amount0: 10)])
        await h.seed(at: 100)
        h.rpc.beforeRequest = { from, _, _ in if from == 131 { throw ScanFailure() } }

        let result = await h.scan(currentBlock: 150, deployBlock: 100)

        #expect(h.cache?.lastSeenBlock == 130)
        #expect(result.fees["1"]?.amount0 == 1)
        #expect(result.bootstrapInProgress)

        h.rpc.beforeRequest = { _, _, _ in }
        let retry = await h.scan(currentBlock: 150, deployBlock: 100)

        #expect(h.cache?.lastSeenBlock == 150)
        #expect(retry.fees["1"]?.amount0 == 11)
        #expect(!retry.bootstrapInProgress)
    }

    @Test func backwardFailureKeepsCeilingAboveFailingChunk() async {
        let h = Harness([.init(block: 95, tokenId: "1", amount0: 1), .init(block: 75, tokenId: "1", amount0: 10)])
        h.rpc.beforeRequest = { from, _, _ in if from == 71 { throw ScanFailure() } }

        let result = await h.scan(currentBlock: 100, deployBlock: 1)

        #expect(h.cache?.nextScanCeiling == 80)
        #expect(result.fees["1"]?.amount0 == 1)
        #expect(result.bootstrapInProgress)

        h.rpc.beforeRequest = { _, _, _ in }
        let retry = await h.scan(currentBlock: 100, deployBlock: 1)

        #expect(h.cache?.nextScanCeiling == nil)
        #expect(retry.fees["1"]?.amount0 == 11)
        #expect(!retry.bootstrapInProgress)
    }

    @Test func partialChunkFailureDoesNotDoubleCount() async {
        // 51 positions → two tokenId batches per chunk; the second batch fails once.
        let h = Harness([.init(block: 105, tokenId: "1", amount0: 1)])
        h.positions = (1...51).map { position(String($0)) }
        await h.seed(at: 100)
        h.rpc.beforeRequest = { from, _, tokenIds in
            if from == 101, tokenIds.contains("51") { throw ScanFailure() }
        }

        let result = await h.scan(currentBlock: 110, deployBlock: 100)

        #expect(h.cache?.lastSeenBlock == 100)
        #expect(result.fees["1"] == nil)

        h.rpc.beforeRequest = { _, _, _ in }
        let retry = await h.scan(currentBlock: 110, deployBlock: 100)

        #expect(h.cache?.lastSeenBlock == 110)
        #expect(retry.fees["1"]?.amount0 == 1)
    }

    @Test func forwardScanStopsAtMaxChunksCap() async {
        let h = Harness([.init(block: 180, tokenId: "1", amount0: 1)])
        await h.seed(at: 100)
        h.maxChunks = 3

        let result = await h.scan(currentBlock: 200, deployBlock: 100)

        #expect(h.cache?.lastSeenBlock == 130)
        #expect(result.bootstrapInProgress)

        h.maxChunks = 100
        let rest = await h.scan(currentBlock: 200, deployBlock: 100)

        #expect(h.cache?.lastSeenBlock == 200)
        #expect(rest.fees["1"]?.amount0 == 1)
    }

    @Test func cancelledScanKeepsOnlyCompletedChunks() async {
        let h = Harness([.init(block: 125, tokenId: "1", amount0: 1)])
        await h.seed(at: 100)
        let entered = Latch()
        let release = Latch()
        h.rpc.beforeRequest = { from, _, _ in
            if from == 121 {
                await entered.open()
                await release.wait()
            }
        }

        let task = Task { await h.scan(currentBlock: 200, deployBlock: 100) }
        await entered.wait()
        task.cancel()
        await release.open()
        _ = await task.value

        #expect(h.cache?.lastSeenBlock == 120)
        #expect(h.cache?.fees["1"] == nil)
        #expect(!h.rpc.requestedRanges.contains { $0.lowerBound > 121 })

        h.rpc.beforeRequest = { _, _, _ in }
        let resumed = await h.scan(currentBlock: 200, deployBlock: 100)

        #expect(h.cache?.lastSeenBlock == 200)
        #expect(resumed.fees["1"]?.amount0 == 1)
    }

    /// A cancelled scan finishing after its replacement must not roll the watermark back.
    @Test func replacedScanCannotOverwriteNewerProgress() async throws {
        let h = Harness([.init(block: 105, tokenId: "1", amount0: 1)])
        await h.seed(at: 100)
        let entered = Latch()
        let release = Latch()
        h.rpc.beforeRequest = { _, to, _ in
            if to == 110 {
                await entered.open()
                await release.wait()
            }
        }

        // A scans to 110 and stalls in its RPC call; it is then cancelled and replaced by B.
        let scanA = Task { await h.scan(currentBlock: 110, deployBlock: 100) }
        await entered.wait()
        scanA.cancel()
        h.rpc.beforeRequest = { _, _, _ in }
        let scanB = Task { await h.scan(currentBlock: 120, deployBlock: 100) }

        // B must wait for A instead of scanning alongside it.
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(h.rpc.requestedRanges.count == 2)  // seed + A's stalled request

        await release.open()
        _ = await scanA.value
        let resultB = await scanB.value

        #expect(h.cache?.lastSeenBlock == 120)
        #expect(resultB.fees["1"]?.amount0 == 1)
    }
}
