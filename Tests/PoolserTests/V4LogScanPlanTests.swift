import Testing
@testable import Poolser

private let deploy = 21_688_329
private let chunkSize = 20_000
private let maxChunks = 120
private let lookback = 24

private func plan(
    head: Int,
    last: Int? = nil,
    nextBootstrap: Int? = nil,
    maxChunks: Int = maxChunks
) -> V4LogScanPlan {
    planV4LogScan(
        deployBlock: deploy,
        currentBlock: head,
        lastScannedBlock: last,
        nextBootstrapFromBlock: nextBootstrap,
        chunkSize: chunkSize,
        maxChunks: maxChunks,
        reorgLookbackBlocks: lookback
    )
}

/// Runs consecutive incremental passes the way loadV4 persists them, returning each plan.
private func catchUp(from last: Int, head: Int, maxChunks: Int) -> [V4LogScanPlan] {
    var plans: [V4LogScanPlan] = []
    var last = last
    while true {
        let p = plan(head: head, last: last, maxChunks: maxChunks)
        plans.append(p)
        last = p.scanEndBlock
        if p.nextFromBlock == nil || plans.count > 1_000 { return plans }
    }
}

@Suite struct V4LogScanPlanTests {
    @Test func smallIncrementalDeltaScansToHeadInOnePass() {
        let p = plan(head: 23_000_100, last: 23_000_000)
        #expect(!p.isBootstrap)
        #expect(p.chunks == [22_999_976...23_000_100])
        #expect(p.scanEndBlock == 23_000_100)
        #expect(p.nextFromBlock == nil)
    }

    /// ~1.38M blocks behind on Ethereum: previously ~70 chunks in a single refresh.
    @Test func longDowntimeIsCappedPerRefresh() {
        let last = 23_000_000
        let head = last + 1_380_000
        let p = plan(head: head, last: last, maxChunks: 10)
        #expect(!p.isBootstrap)
        #expect(p.chunks.count == 10)
        #expect(p.chunks.first?.lowerBound == last - lookback)
        #expect(p.scanEndBlock == last - lookback + 10 * chunkSize - 1)
        #expect(p.nextFromBlock == p.scanEndBlock + 1)
    }

    @Test(arguments: [5, 37, 120, 200])
    func incrementalNeverExceedsChunkCap(maxChunks: Int) {
        // About a month of Arbitrum blocks.
        let p = plan(head: 300_000_000 + 10_400_000, last: 300_000_000, maxChunks: maxChunks)
        #expect(p.chunks.count <= maxChunks)
        #expect(p.chunks.allSatisfy { $0.count <= chunkSize })
    }

    @Test func catchUpPassesCoverEveryBlockAndEndAtHead() {
        let last = 23_000_000
        let head = last + 1_380_000
        let plans = catchUp(from: last, head: head, maxChunks: 10)

        #expect(plans.count == 7)
        #expect(plans.allSatisfy { !$0.isBootstrap && $0.chunks.count <= 10 })
        #expect(plans.last?.scanEndBlock == head)
        #expect(plans.last?.nextFromBlock == nil)

        // Progress is monotonic and consecutive passes overlap (reorg lookback), never gap.
        let ranges = plans.flatMap(\.chunks)
        #expect(ranges.first?.lowerBound == last - lookback)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(b.lowerBound <= a.upperBound + 1)
            #expect(b.upperBound > a.upperBound)
        }
        for (a, b) in zip(plans, plans.dropFirst()) {
            #expect(b.scanEndBlock > a.scanEndBlock)
        }
    }

    @Test func firstBootstrapStartsAtDeployBlockAndIsCapped() {
        let p = plan(head: deploy + 5_000_000)
        #expect(p.isBootstrap)
        #expect(p.chunks.first == deploy...(deploy + chunkSize - 1))
        #expect(p.chunks.count == maxChunks)
        #expect(p.nextFromBlock == deploy + maxChunks * chunkSize)
    }

    @Test func bootstrapContinuationResumesExactlyAtNextBlock() {
        let next = deploy + 2_400_000
        let p = plan(head: deploy + 2_500_000, last: next - 1, nextBootstrap: next)
        #expect(p.isBootstrap)
        #expect(p.chunks.first?.lowerBound == next)
        #expect(p.scanEndBlock == deploy + 2_500_000)
        #expect(p.nextFromBlock == nil)
    }

    @Test func incrementalStartNeverPrecedesDeployBlock() {
        let p = plan(head: deploy + 100, last: deploy + 10)
        #expect(p.chunks == [deploy...(deploy + 100)])
    }

    @Test func laggingHeadScansNothingAndKeepsProgress() {
        let p = plan(head: 23_000_000, last: 23_000_500)
        #expect(p.chunks.isEmpty)
        #expect(p.scanEndBlock == 23_000_500)
        #expect(p.nextFromBlock == nil)
    }

    @Test func laggingHeadDuringBootstrapKeepsBootstrapPosition() {
        let next = deploy + 1_000_000
        let p = plan(head: next - 10, last: next - 1, nextBootstrap: next)
        #expect(p.chunks.isEmpty)
        #expect(p.isBootstrap)
        #expect(p.scanEndBlock == next - 1)
        #expect(p.nextFromBlock == next)
    }

    @Test func chunksAreContiguousAndEndAtScanEnd() {
        let p = plan(head: 23_000_000 + 55_555, last: 23_000_000)
        #expect(p.chunks.count == 3)
        for (a, b) in zip(p.chunks, p.chunks.dropFirst()) {
            #expect(b.lowerBound == a.upperBound + 1)
        }
        #expect(p.chunks.last?.upperBound == p.scanEndBlock)
    }
}
