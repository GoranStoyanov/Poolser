import Foundation
import Testing
@testable import Poolser

@Suite struct RPCCreditLimiterTests {
    @Test func acquireTakesAvailableCredits() async throws {
        let limiter = RPCCreditLimiter(creditsPerSecond: 1, maxBurstCredits: 10)
        try await limiter.acquire(credits: 4)
        #expect(await limiter.availableCredits == 6)
    }

    @Test func acquireWaitsForRefill() async throws {
        let limiter = RPCCreditLimiter(creditsPerSecond: 100, maxBurstCredits: 10)
        try await limiter.acquire(credits: 10)
        let start = ContinuousClock.now
        try await limiter.acquire(credits: 5)
        #expect(ContinuousClock.now - start >= .milliseconds(40))
    }

    /// A waiter must leave as soon as it is cancelled; it used to spin until credits refilled.
    @Test func cancellingWaiterThrowsPromptly() async throws {
        let limiter = RPCCreditLimiter(creditsPerSecond: 1, maxBurstCredits: 1)
        let waiter = Task { try await limiter.acquire(credits: 100) }
        try await Task.sleep(for: .milliseconds(50))

        let start = ContinuousClock.now
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(ContinuousClock.now - start < .seconds(1))

        // The burst credit was never taken, so the next caller gets it right away.
        let next = ContinuousClock.now
        try await limiter.acquire(credits: 1)
        #expect(ContinuousClock.now - next < .milliseconds(500))
    }

    @Test func cancelledCallerTakesNoCredits() async throws {
        let limiter = RPCCreditLimiter(creditsPerSecond: 1, maxBurstCredits: 10)
        let caller = Task {
            // Returns early once the task is cancelled.
            try? await Task.sleep(for: .seconds(60))
            try await limiter.acquire(credits: 10)
        }
        caller.cancel()
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(await limiter.availableCredits == 10)
    }
}

@Suite struct RPCCancellationRetryTests {
    private let client = EthereumClient(rpcURL: URL(string: "http://127.0.0.1:9")!)

    @Test func cancellationIsNotRetried() {
        #expect(!client.shouldRetry(CancellationError()))
        #expect(!client.shouldRetry(URLError(.cancelled)))
    }

    @Test func networkFailureIsRetried() {
        #expect(client.shouldRetry(URLError(.timedOut)))
    }

    @Test func cancelledRequestThrowsCancellation() async {
        let client = client
        let request = Task {
            try? await Task.sleep(for: .seconds(60))
            return try await client.ethCall(to: "0x0000000000000000000000000000000000000000", data: Data())
        }
        request.cancel()
        await #expect(throws: CancellationError.self) { try await request.value }
    }
}
