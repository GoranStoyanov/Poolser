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
        let limiter = RPCCreditLimiter(creditsPerSecond: 1, maxBurstCredits: 100)
        try await limiter.acquire(credits: 100)  // empty the bucket: the next caller must wait ~100 s
        let waiter = Task { try await limiter.acquire(credits: 100) }
        try await Task.sleep(for: .milliseconds(50))

        let start = ContinuousClock.now
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(ContinuousClock.now - start < .seconds(1))

        // The waiter took nothing: the bucket holds only what refilled in the meantime.
        #expect(await limiter.availableCredits < 5)
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

        clock.advance(RPCCreditLimiter.defaultPause + RPCCreditLimiter.penaltyWindow)
        #expect(await limiter.noteRateLimited() == 100)
    }

    @Test func paceNeverDropsBelowFloor() async {
        let clock = ManualClock()
        let limiter = limiter(clock)
        for _ in 0..<10 {
            await limiter.noteRateLimited()
            clock.advance(RPCCreditLimiter.defaultPause + RPCCreditLimiter.penaltyWindow)
        }
        #expect(await limiter.throttle == RPCCreditLimiter.minThrottle)
        #expect(await limiter.effectiveCreditsPerSecond == 400 * RPCCreditLimiter.minThrottle)
        #expect(await limiter.noteRateLimited() == nil)
    }

    @Test func paceRecoversStepByStepWithoutNewRateLimits() async throws {
        let clock = ManualClock()
        let limiter = limiter(clock)
        await limiter.noteRateLimited()                       // 0.5, paused for defaultPause
        clock.advance(RPCCreditLimiter.defaultPause + RPCCreditLimiter.recoveryInterval - 1)
        try await limiter.acquire(credits: 1)                 // triggers refill/recovery
        #expect(await limiter.throttle == 0.5)

        clock.advance(1)
        try await limiter.acquire(credits: 1)
        #expect(await limiter.throttle == 0.5 + RPCCreditLimiter.recoveryStep)

        // The pace climbs back only to 80% of the pace that hit the limit...
        clock.advance(RPCCreditLimiter.recoveryInterval * 10)
        try await limiter.acquire(credits: 1)
        #expect(await limiter.throttle == RPCCreditLimiter.ceilingFactor)
        #expect(await limiter.effectiveCreditsPerSecond == 320)

        // ...and that ceiling rises again after a long stretch without rate limits.
        clock.advance(RPCCreditLimiter.ceilingRecoveryInterval * 2)
        try await limiter.acquire(credits: 1)
        #expect(await limiter.throttle == 1)
        #expect(await limiter.effectiveCreditsPerSecond == 400)
    }

    @Test func refillUsesLoweredPace() async throws {
        let clock = ManualClock()
        let limiter = RPCCreditLimiter(creditsPerSecond: 400, maxBurstCredits: 10_000, now: { clock.now })
        await limiter.noteRateLimited()                       // 200 credits/s, bucket empty, 2 s pause
        clock.advance(RPCCreditLimiter.defaultPause + 0.5)
        try await limiter.acquire(credits: 500)               // exactly 2.5 s × 200
        #expect(await limiter.availableCredits == 0)
    }

    @Test func ceilingFollowsThePaceThatHitTheLimit() async {
        let clock = ManualClock()
        let limiter = limiter(clock)
        await limiter.noteRateLimited()                       // hit at 1.0: ceiling 0.8, pace 0.5
        #expect(await limiter.ceiling == 0.8)
        clock.advance(RPCCreditLimiter.defaultPause + RPCCreditLimiter.penaltyWindow)
        await limiter.noteRateLimited()                       // hit at 0.5: ceiling 0.4, pace 0.25
        #expect(await limiter.ceiling == 0.4)
        #expect(await limiter.ceilingCreditsPerSecond == 160)
    }

    @Test func newBudgetForgetsTheCeiling() async {
        let clock = ManualClock()
        let limiter = limiter(clock)
        await limiter.noteRateLimited()
        await limiter.configure(creditsPerSecond: 400, maxBurstCredits: 255)
        #expect(await limiter.ceiling == 0.8)                 // same budget: kept
        await limiter.configure(creditsPerSecond: 300, maxBurstCredits: 255)
        #expect(await limiter.ceiling == 1)
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

@Suite("RPC credit limiter: provider backoff and burst")
struct RPCCreditLimiterBackoffTests {
    @Test func providerBackoffPausesEveryRequest() async {
        let clock = ManualClock()
        let limiter = RPCCreditLimiter(creditsPerSecond: 400, maxBurstCredits: 255, now: { clock.now })

        await limiter.noteRateLimited(pauseFor: 30)
        #expect(await limiter.pauseRemaining == 30)
        clock.advance(10)
        #expect(await limiter.pauseRemaining == 20)
        // A later, shorter hint never shortens a pause already in force.
        await limiter.noteRateLimited(pauseFor: 5)
        #expect(await limiter.pauseRemaining == 20)
    }

    @Test func providerBackoffIsCapped() async {
        let clock = ManualClock()
        let limiter = RPCCreditLimiter(creditsPerSecond: 400, maxBurstCredits: 255, now: { clock.now })
        await limiter.noteRateLimited(pauseFor: 3_600)
        #expect(await limiter.pauseRemaining == RPCCreditLimiter.maxPause)
    }

    /// Infura's 429 carries no backoff hint; every request still pauses briefly.
    @Test func rateLimitWithoutHintPausesBriefly() async {
        let clock = ManualClock()
        let limiter = RPCCreditLimiter(creditsPerSecond: 400, maxBurstCredits: 255, now: { clock.now })
        await limiter.noteRateLimited()
        #expect(await limiter.pauseRemaining == RPCCreditLimiter.defaultPause)
        // A 429 that arrives during the pause was already in flight: nothing changes.
        clock.advance(1)
        #expect(await limiter.noteRateLimited() == nil)
        #expect(await limiter.pauseRemaining == 1)
        // A 429 right after the pause is the same episode: a longer pause, the same pace.
        clock.advance(1)
        #expect(await limiter.noteRateLimited() == nil)
        #expect(await limiter.pauseRemaining == RPCCreditLimiter.defaultPause * 2)
        #expect(await limiter.effectiveCreditsPerSecond == 200)
    }

    /// Infura kept refusing for ~8 s after a limit; retries 2 s apart used up most of their tries.
    @Test func pauseDoublesWithinAnEpisode() async {
        let clock = ManualClock()
        let limiter = RPCCreditLimiter(creditsPerSecond: 400, maxBurstCredits: 255, now: { clock.now })
        var pauses: [TimeInterval] = []
        for _ in 0..<6 {
            await limiter.noteRateLimited()
            let pause = await limiter.pauseRemaining
            pauses.append(pause)
            clock.advance(pause)                              // each retry goes out when the pause ends
        }
        #expect(pauses == [2, 4, 8, 16, 30, 30])
        #expect(await limiter.effectiveCreditsPerSecond == 200)
    }

    @Test func quietGapStartsANewEpisode() async {
        let clock = ManualClock()
        let limiter = RPCCreditLimiter(creditsPerSecond: 400, maxBurstCredits: 255, now: { clock.now })
        await limiter.noteRateLimited()
        clock.advance(2)
        await limiter.noteRateLimited()                       // 4 s pause, same episode
        clock.advance(4 + RPCCreditLimiter.penaltyWindow)
        #expect(await limiter.noteRateLimited() == 100)       // new episode: lowered again
        #expect(await limiter.pauseRemaining == RPCCreditLimiter.defaultPause)
    }

    /// A budget below one getLogs (255 credits) used to leave such requests waiting forever.
    @Test func requestLargerThanBucketStillStarts() async throws {
        let limiter = RPCCreditLimiter(creditsPerSecond: 50, maxBurstCredits: 100)
        try await limiter.acquire(credits: 255)
        #expect(await limiter.availableCredits == 0)
    }

    @Test(arguments: [
        ("5", "", 5.0),
        (nil, #"{"error":{"code":-32005,"message":"project ID request rate exceeded","data":{"backoff_seconds":30}}}"#, 30.0),
        (nil, #"{"error":{"code":429,"message":"Too Many Requests","data":{"rate":{"backoff_seconds":2.5}}}}"#, 2.5),
        ("600", "", 60.0),
    ] as [(String?, String, Double)])
    func providerBackoffHints(retryAfter: String?, body: String, expected: Double) {
        #expect(EthereumClient.providerBackoff(retryAfter: retryAfter, body: Data(body.utf8)) == expected)
    }

    @Test(arguments: [
        (nil, ""),
        (nil, #"{"error":{"message":"Too Many Requests"}}"#),
        ("Wed, 21 Oct 2026 07:28:00 GMT", ""),
        ("0", ""),
    ] as [(String?, String)])
    func noBackoffHint(retryAfter: String?, body: String) {
        #expect(EthereumClient.providerBackoff(retryAfter: retryAfter, body: Data(body.utf8)) == nil)
    }
}

