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

/// Hand-driven time for the limiter's throttle tests.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: TimeInterval = 1_000

    var now: TimeInterval { lock.withLock { t } }
    func advance(_ seconds: TimeInterval) { lock.withLock { t += seconds } }
}

@Suite struct RPCCreditLimiterThrottleTests {
    private func limiter(_ clock: ManualClock, cps: Double = 400) -> RPCCreditLimiter {
        RPCCreditLimiter(creditsPerSecond: cps, maxBurstCredits: cps, now: { clock.now })
    }

    @Test func rateLimitHalvesPaceAndEmptiesBucket() async {
        let clock = ManualClock()
        let limiter = limiter(clock)
        #expect(await limiter.noteRateLimited() == 200)
        #expect(await limiter.effectiveCreditsPerSecond == 200)
        #expect(await limiter.availableCredits == 0)
    }

    /// Parallel requests from one burst all get 429; that must lower the pace one step, not five.
    @Test func burstOfRateLimitsCountsOnce() async {
        let clock = ManualClock()
        let limiter = limiter(clock)
        await limiter.noteRateLimited()
        for _ in 0..<4 { #expect(await limiter.noteRateLimited() == nil) }
        #expect(await limiter.effectiveCreditsPerSecond == 200)

        clock.advance(RPCCreditLimiter.penaltyWindow)
        #expect(await limiter.noteRateLimited() == 100)
    }

    @Test func paceNeverDropsBelowFloor() async {
        let clock = ManualClock()
        let limiter = limiter(clock)
        for _ in 0..<10 {
            await limiter.noteRateLimited()
            clock.advance(RPCCreditLimiter.penaltyWindow)
        }
        #expect(await limiter.throttle == RPCCreditLimiter.minThrottle)
        #expect(await limiter.effectiveCreditsPerSecond == 400 * RPCCreditLimiter.minThrottle)
        #expect(await limiter.noteRateLimited() == nil)
    }

    @Test func paceRecoversStepByStepWithoutNewRateLimits() async throws {
        let clock = ManualClock()
        let limiter = limiter(clock)
        await limiter.noteRateLimited()                       // 0.5
        clock.advance(RPCCreditLimiter.recoveryInterval - 1)
        try await limiter.acquire(credits: 1)                 // triggers refill/recovery
        #expect(await limiter.throttle == 0.5)

        clock.advance(1)
        try await limiter.acquire(credits: 1)
        #expect(await limiter.throttle == 0.5 + RPCCreditLimiter.recoveryStep)

        clock.advance(RPCCreditLimiter.recoveryInterval * 10)
        try await limiter.acquire(credits: 1)
        #expect(await limiter.throttle == 1)
        #expect(await limiter.effectiveCreditsPerSecond == 400)
    }

    @Test func refillUsesLoweredPace() async throws {
        let clock = ManualClock()
        let limiter = limiter(clock)
        await limiter.noteRateLimited()                       // 200 credits/s, bucket empty
        clock.advance(0.5)
        try await limiter.acquire(credits: 100)               // exactly 0.5 s × 200
        #expect(await limiter.availableCredits == 0)
    }
}

@Suite struct RateLimitDetectionTests {
    @Test(arguments: [
        "HTTP 429",
        "HTTP 429: project ID request rate exceeded",
        "too many requests",
        "Rate limit reached",
    ])
    func rateLimitMessages(_ message: String) {
        #expect(EthereumClient.isRateLimit(EthereumClient.Err.rpc(message)))
    }

    @Test(arguments: ["HTTP 500", "header not found", "execution reverted"])
    func otherErrorsAreNotRateLimits(_ message: String) {
        #expect(!EthereumClient.isRateLimit(EthereumClient.Err.rpc(message)))
    }

    @Test func nonRPCErrorsAreNotRateLimits() {
        #expect(!EthereumClient.isRateLimit(URLError(.timedOut)))
        #expect(!EthereumClient.isRateLimit(EthereumClient.Err.noResult))
    }
}
