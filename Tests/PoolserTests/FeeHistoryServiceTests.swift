import Foundation
import Testing
@testable import Poolser

private let collectTopic = "0x40d0efd1a53d60ecbf40971b9daf7dc90178c3aadc7aab1765632738fa8b8f01"
private let decreaseLiquidityTopic = "0x26f6a048ee9138f2c0ce266f322cb99228e8d619ae2bff30c67f8dcf9d2377b4"
private let increaseLiquidityTopic = "0x3067048beee31b25b2f1681f88dac838c8bba36af25bfb2b7cf7473a5847e35f"
private let chainID = "test"

/// In-memory NFPM log source with scriptable failures.
private final class FakeRPC: @unchecked Sendable {
    struct Event {
        let block: Int
        let tokenId: String
        let amount0: Int
        var amount1 = 0
        var topic = collectTopic

        static func decrease(block: Int, tokenId: String, amount0: Int, amount1: Int = 0) -> Event {
            Event(block: block, tokenId: tokenId, amount0: amount0, amount1: amount1, topic: decreaseLiquidityTopic)
        }

        static func increase(block: Int, tokenId: String) -> Event {
            Event(block: block, tokenId: tokenId, amount0: 0, topic: increaseLiquidityTopic)
        }
    }

    private let lock = NSLock()
    private var events: [Event]
    private var calls: [(from: Int, to: Int, tokenIds: [String])] = []
    private var hook: (_ from: Int, _ to: Int, _ tokenIds: [String]) async throws -> Void = { _, _, _ in }

    /// Called before each request; throw to fail it.
    var beforeRequest: (_ from: Int, _ to: Int, _ tokenIds: [String]) async throws -> Void {
        get { lock.withLock { hook } }
        set { lock.withLock { hook = newValue } }
    }

    init(_ events: [Event]) {
        self.events = events
    }

    var requestedRanges: [ClosedRange<Int>] {
        lock.withLock { calls.map { $0.from...$0.to } }
    }

    func fetch(topics: [[String]?], from: Int, to: Int) async throws -> [[String: Any]] {
        let eventTopics = topics[0] ?? []
        let tokenIds = (topics[1] ?? []).compactMap { UInt64($0.dropFirst(2), radix: 16) }.map(String.init)
        lock.withLock { calls.append((from, to, tokenIds)) }
        try await beforeRequest(from, to, tokenIds)
        return lock.withLock {
            events
                .filter { (from...to).contains($0.block) && tokenIds.contains($0.tokenId) && eventTopics.contains($0.topic) }
                .map(Self.encode)
        }
    }

    private static func encode(_ e: Event) -> [String: Any] {
        let word = { (v: Int) in String(format: "%064x", v) }
        return [
            "topics": [e.topic, "0x" + word(Int(e.tokenId)!)],
            "data": "0x" + word(0) + word(e.amount0) + word(e.amount1),
            "blockNumber": "0x" + String(e.block, radix: 16),
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
    /// Answers the creation-block lookup; nil leaves the scan without one.
    var creationBlock: Int?
    private(set) var creationLookups: [String] = []
    /// Answers block-timestamp reads as `block * 10`; nil leaves positions without an open date.
    var readsTimestamps = false
    private(set) var timestampReads: [Int] = []

    init(_ events: [FakeRPC.Event] = []) {
        store = UserDefaults(suiteName: suiteName)!
        rpc = FakeRPC(events)
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
        let finder: FeeHistoryService.CreationBlockFinder? = creationBlock.map { block in
            { [weak self] tokenId in
                self?.creationLookups.append(tokenId)
                return block
            }
        }
        return await FeeHistoryService.scan(
            positions: positions,
            deployBlock: deployBlock,
            currentBlock: currentBlock,
            chainID: chainID,
            wallet: wallet,
            chunkSize: chunkSize,
            maxChunks: maxChunks,
            store: store,
            findCreationBlock: finder,
            blockTimestamp: readsTimestamps ? { [weak self] block in
                self?.timestampReads.append(block)
                return block * 10
            } : nil
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

    // MARK: - Claimed fees exclude withdrawn principal

    @Test func eventTopicsMatchSignatures() {
        let hex = { (sig: String) in "0x" + keccak256(Data(sig.utf8)).map { String(format: "%02x", $0) }.joined() }
        #expect(hex("Collect(uint256,address,uint256,uint256)") == collectTopic)
        #expect(hex("DecreaseLiquidity(uint256,uint128,uint256,uint256)") == decreaseLiquidityTopic)
    }

    @Test func collectOnlyCountsAsClaimed() async {
        let h = Harness([.init(block: 50, tokenId: "1", amount0: 2, amount1: 600)])

        let result = await h.scan(currentBlock: 100, deployBlock: 1)

        #expect(result.fees["1"]?.amount0 == 2)
        #expect(result.fees["1"]?.amount1 == 600)
    }

    @Test func withdrawalInSameBlockIsNotClaimed() async {
        let h = Harness([
            .init(block: 40, tokenId: "1", amount0: 2, amount1: 600),
            .decrease(block: 70, tokenId: "1", amount0: 50, amount1: 15_000),
            .init(block: 70, tokenId: "1", amount0: 51, amount1: 15_030),
        ])

        let result = await h.scan(currentBlock: 100, deployBlock: 1)

        #expect(result.fees["1"]?.amount0 == 3)
        #expect(result.fees["1"]?.amount1 == 630)
        #expect(h.cache?.fees["1"]?.withdrawn0 == 50)
    }

    @Test func multiplePartialWithdrawalsAcrossScans() async {
        let h = Harness([
            .decrease(block: 30, tokenId: "1", amount0: 10),
            .init(block: 30, tokenId: "1", amount0: 11),
            .decrease(block: 130, tokenId: "1", amount0: 20),
            .init(block: 130, tokenId: "1", amount0: 22),
        ])
        await h.scan(currentBlock: 100, deployBlock: 1)

        let result = await h.scan(currentBlock: 150, deployBlock: 1)

        #expect(result.fees["1"]?.amount0 == 3)
    }

    @Test func uncollectedWithdrawalNeverGoesNegative() async {
        let h = Harness([
            .init(block: 20, tokenId: "1", amount0: 1),
            .decrease(block: 60, tokenId: "1", amount0: 10),
        ])

        let result = await h.scan(currentBlock: 100, deployBlock: 1)

        #expect(result.fees["1"]?.amount0 == 0)
    }
}

@Suite("Fee history creation block")
struct FeeHistoryCreationBlockTests {
    @Test func backwardScanStopsAtTheOldestPositionsCreationBlock() async {
        // Minted at 110, liquidity added again at 150: a collect in between must still count.
        let h = Harness([
            .increase(block: 110, tokenId: "1"),
            .init(block: 120, tokenId: "1", amount0: 7),
            .increase(block: 150, tokenId: "1"),
        ])
        h.creationBlock = 110

        let result = await h.scan(currentBlock: 200, deployBlock: 0)

        #expect(!result.bootstrapInProgress)
        #expect(result.fees["1"]?.amount0 == 7)
        #expect(h.rpc.requestedRanges.map(\.lowerBound).min() == 110)
        #expect(h.cache?.creationBlocks["1"] == 110)
    }

    @Test func withoutCreationBlockTheScanKeepsItsOldBound() async {
        let h = Harness([.increase(block: 110, tokenId: "1"), .init(block: 120, tokenId: "1", amount0: 7)])

        let result = await h.scan(currentBlock: 200, deployBlock: 0)

        #expect(result.fees["1"]?.amount0 == 7)
        #expect(h.cache?.creationBlocks.isEmpty == true)
    }

    @Test func oldestTokenIsLookedUpOnceAndCached() async {
        let h = Harness()
        h.positions = [position("30"), position("4"), position("100")]
        h.creationBlock = 150
        h.maxChunks = 3  // 200→150 is 6 chunks of 10 blocks: two scans

        await h.scan(currentBlock: 200, deployBlock: 0)
        await h.scan(currentBlock: 200, deployBlock: 0)

        // "4" is the smallest id, so the oldest position, even though "100" sorts first as text.
        #expect(h.creationLookups == ["4"])
        #expect(h.cache?.nextScanCeiling == nil)
    }

    @Test func firstBlockFindsTheMintWithLogarithmicReads() async {
        var reads = 0
        let block = await FeeHistoryService.firstBlock(after: 999, upTo: 1_000_000) { b in
            reads += 1
            return b >= 24_555
        }
        #expect(block == 24_555)
        #expect(reads <= 20)
    }

    @Test func firstBlockGivesUpWhenAReadFails() async {
        let block = await FeeHistoryService.firstBlock(after: 0, upTo: 1_000) { b in
            if b < 500 { throw ScanFailure() }
            return b >= 300
        }
        #expect(block == nil)
    }

    @Test func knownStartIgnoresThePerRefreshCap() async {
        let h = Harness([.init(block: 120, tokenId: "1", amount0: 3)])
        h.creationBlock = 100
        h.maxChunks = 2  // 200→100 is 11 chunks of 10 blocks

        let result = await h.scan(currentBlock: 200, deployBlock: 0)

        #expect(!result.bootstrapInProgress)
        #expect(result.fees["1"]?.amount0 == 3)
    }

    @Test func unknownStartKeepsThePerRefreshCap() async {
        let h = Harness()
        h.maxChunks = 2

        let result = await h.scan(currentBlock: 200, deployBlock: 0)

        #expect(result.bootstrapInProgress)
        #expect(h.rpc.requestedRanges.count == 2)
    }

    @Test func progressIsSavedAfterEveryChunk() async {
        let h = Harness()
        h.creationBlock = 100
        let key = FeeHistoryService.cacheKey(chainID: chainID, wallet: h.wallet)
        let store = h.store
        var ceilingsSeen: [Int?] = []
        h.rpc.beforeRequest = { _, _, _ in
            ceilingsSeen.append(FeeHistoryService.loadCache(forKey: key, store: store)?.nextScanCeiling)
        }

        await h.scan(currentBlock: 200, deployBlock: 0)

        // Each request sees the ceiling the previous chunk saved: 200, 190, 180, …
        #expect(Array(ceilingsSeen.dropFirst().prefix(3)) == [190, 180, 170])
    }
}

@Suite("Fee history open dates")
struct FeeHistoryOpenDateTests {
    @Test func completeHistoryReportsEachPositionsOpenDate() async {
        let h = Harness([.increase(block: 120, tokenId: "1"), .increase(block: 160, tokenId: "2"), .increase(block: 170, tokenId: "2")])
        h.positions = [position("1"), position("2")]
        h.creationBlock = 120
        h.readsTimestamps = true

        let result = await h.scan(currentBlock: 200, deployBlock: 0)

        #expect(!result.bootstrapInProgress)
        #expect(result.openedAt["1"] == Date(timeIntervalSince1970: 1_200))
        // The earliest IncreaseLiquidity is the mint once the history is complete.
        #expect(result.openedAt["2"] == Date(timeIntervalSince1970: 1_600))
    }

    @Test func noOpenDateWhileBootstrapping() async {
        let h = Harness([.increase(block: 150, tokenId: "1")])
        h.maxChunks = 2
        h.readsTimestamps = true

        let result = await h.scan(currentBlock: 200, deployBlock: 0)

        #expect(result.bootstrapInProgress)
        #expect(result.openedAt.isEmpty)
        #expect(h.timestampReads.isEmpty)
    }

    @Test func openDateIsReadOnce() async {
        let h = Harness([.increase(block: 150, tokenId: "1")])
        h.creationBlock = 150
        h.readsTimestamps = true

        await h.scan(currentBlock: 200, deployBlock: 0)
        let again = await h.scan(currentBlock: 210, deployBlock: 0)

        #expect(h.timestampReads == [150])
        #expect(again.openedAt["1"] == Date(timeIntervalSince1970: 1_500))
    }
}

