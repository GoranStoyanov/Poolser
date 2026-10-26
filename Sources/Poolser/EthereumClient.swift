import Foundation

struct EthereumClient {
    /// Sends one HTTP request and returns the raw response; injectable so tests can replace the network.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let rpcURL: URL
    private let transport: Transport
    // Infura free tier nominal throughput is 500 credits/sec.
    // App default keeps a safety margin to reduce bursty 429s.
    private static let defaultBudgetCreditsPerSecond = 400
    /// The costliest single request (eth_getLogs). Saved-up credits never exceed it: a burst of
    /// a full second's budget on top of the pace sent ~800 credits in the first second of a
    /// refresh, over Infura's 500/s. It must cover one request, or getLogs could never start
    /// on a budget below its cost.
    private static let maxBurstCredits = 255.0
    private static let sharedLimiter = RPCCreditLimiter(
        creditsPerSecond: Double(defaultBudgetCreditsPerSecond),
        maxBurstCredits: maxBurstCredits
    )
    private let limiter: RPCCreditLimiter
    private let costEthCall = 80
    private let costEthGetLogs = 255
    private let costEthBlockNumber = 80
    private let costEthChainId = 80
    private let costEthGetBlock = 80
    private let costEthEstimateGas = 300
    private let costEthGasPrice = 80
    private let callMaxRetries = 3
    private let logsMaxRetries = 4
    private let blockNumberMaxRetries = 2
    private let chainIdMaxRetries = 2

    /// Every client shares one limiter unless a test passes its own.
    init(
        rpcURL: URL,
        limiter: RPCCreditLimiter? = nil,
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.rpcURL = rpcURL
        self.limiter = limiter ?? Self.sharedLimiter
        self.transport = transport
    }

    /// Shared by every client. Called with a value read on the main actor at the start of a
    /// load, so request code never touches `AppSettings`.
    static func setCreditBudget(perSecond credits: Int) async {
        await sharedLimiter.configure(creditsPerSecond: Double(credits), maxBurstCredits: maxBurstCredits)
    }

    enum Err: Error, LocalizedError {
        case rpc(String)
        /// The contract call itself reverted (e.g. ownerOf on a burned token) — deterministic, not retried.
        case reverted(String)
        case noResult
        case badJSON

        var errorDescription: String? {
            switch self {
            case .rpc(let m):      return "RPC: \(m)"
            case .reverted(let m): return "RPC: \(m)"
            case .noResult:        return "No result in RPC response"
            case .badJSON:         return "Invalid JSON from RPC"
            }
        }

        /// JSON-RPC error code 3 is geth's "execution reverted"; some providers only say so in the message.
        static func isRevert(code: Any?, message: String) -> Bool {
            if let code = code as? Int, code == 3 { return true }
            return message.lowercased().contains("execution reverted")
        }
    }

    func ethBlockNumber() async throws -> Int {
        try await rpc(RPCSpec(
            method: "eth_blockNumber", params: [], cost: costEthBlockNumber,
            maxRetries: blockNumberMaxRetries, timeout: 15, label: "eth_blockNumber", logsErrors: false
        ), decode: decodeQuantity)
    }

    /// Unix time of a block, from eth_getBlockByNumber without its transactions.
    func ethBlockTimestamp(_ block: Int) async throws -> Int {
        try await rpc(RPCSpec(
            method: "eth_getBlockByNumber", params: ["0x" + String(block, radix: 16), false], cost: costEthGetBlock,
            maxRetries: blockNumberMaxRetries, timeout: 15, label: "eth_getBlockByNumber",
            requestDetail: "\(block)"
        )) { raw in
            guard let header = raw as? [String: Any], let timestamp = header["timestamp"] else { return nil }
            return try self.decodeQuantity(timestamp)
        }
    }

    func ethChainId() async throws -> Int {
        try await rpc(RPCSpec(
            method: "eth_chainId", params: [], cost: costEthChainId,
            maxRetries: chainIdMaxRetries, timeout: 15, label: "eth_chainId", logsErrors: false
        ), decode: decodeQuantity)
    }

    /// eth_getLogs query. Pass `nil` in `topics` to match any value at that position.
    func ethGetLogs(
        address: String,
        topics: [String?],
        fromBlock: String,
        toBlock: String = "latest",
        context: String? = nil
    ) async throws -> [[String: Any]] {
        let jsonTopics: [Any] = topics.map { t -> Any in
            guard let t = t else { return NSNull() }
            return t
        }
        return try await getLogs(
            address: address, jsonTopics: jsonTopics, fromBlock: fromBlock, toBlock: toBlock,
            label: "getLogs" + (context.map { " \($0)" } ?? ""),
            noResultNote: " (null response from RPC)"
        )
    }

    /// eth_getLogs with OR semantics per topic position.
    /// Each element is nil (match any) or an array of hex strings (OR match).
    func ethGetLogsOR(
        address: String,
        topics: [[String]?],
        fromBlock: String,
        toBlock: String = "latest",
        context: String? = nil
    ) async throws -> [[String: Any]] {
        let jsonTopics: [Any] = topics.map { t -> Any in
            guard let t = t else { return NSNull() }
            return t.count == 1 ? t[0] : t
        }
        return try await getLogs(
            address: address, jsonTopics: jsonTopics, fromBlock: fromBlock, toBlock: toBlock,
            label: "getLogs(OR)" + (context.map { " \($0)" } ?? ""),
            noResultNote: ""
        )
    }

    private func getLogs(
        address: String,
        jsonTopics: [Any],
        fromBlock: String,
        toBlock: String,
        label: String,
        noResultNote: String
    ) async throws -> [[String: Any]] {
        let range = "\(fromBlock)–\(toBlock)"
        let logs = try await rpc(RPCSpec(
            method: "eth_getLogs",
            params: [["address":   address,
                      "topics":    jsonTopics,
                      "fromBlock": fromBlock,
                      "toBlock":   toBlock]],
            cost: costEthGetLogs, maxRetries: logsMaxRetries, timeout: 30, label: label,
            requestDetail: "\(short(address)) \(range)",
            noResultDetail: "\(noResultNote) \(short(address)) \(range)",
            retryDetail: " \(range)"
        )) { $0 as? [[String: Any]] }
        log("\(label) ← \(logs.count) events", level: .response)
        return logs
    }

    func ethCall(to: String, data: Data) async throws -> Data {
        let selector = data.count >= 4 ? data.prefix(4).hexString : data.hexString
        let resultData = try await call(to: to, data: data, label: "eth_call", target: "\(short(to)) \(selector)")
        log("eth_call ← \(resultData.count)B", level: .response)
        return resultData
    }

    /// eth_call as if `from` sent it: a dry run of a transaction that checks `msg.sender`.
    func ethCall(to: String, data: Data, from: String) async throws -> Data {
        let selector = data.count >= 4 ? data.prefix(4).hexString : data.hexString
        let resultData = try await call(
            to: to, data: data, label: "eth_call", target: "\(short(to)) \(selector) from \(short(from))", from: from
        )
        log("eth_call ← \(resultData.count)B", level: .response)
        return resultData
    }

    /// eth_estimateGas for a transaction from `from`. It executes the transaction, so a revert
    /// throws `Err.reverted` like a dry run.
    func ethEstimateGas(to: String, data: Data, from: String) async throws -> Int {
        let selector = data.count >= 4 ? data.prefix(4).hexString : data.hexString
        let target = "\(short(to)) \(selector) from \(short(from))"
        let gas = try await rpc(RPCSpec(
            method: "eth_estimateGas", params: [["to": to, "data": "0x" + data.hexString, "from": from]],
            cost: costEthEstimateGas, maxRetries: callMaxRetries, timeout: 15, label: "eth_estimateGas",
            requestDetail: target, noResultDetail: ": \(target)", retryDetail: " \(target)", detectsRevert: true
        ), decode: decodeQuantity)
        log("eth_estimateGas ← \(gas)", level: .response)
        return gas
    }

    /// Current gas price in wei.
    func ethGasPrice() async throws -> Int {
        try await rpc(RPCSpec(
            method: "eth_gasPrice", params: [], cost: costEthGasPrice,
            maxRetries: callMaxRetries, timeout: 15, label: "eth_gasPrice"
        ), decode: decodeQuantity)
    }

    /// eth_call against the state at a past block. Needs a node that serves historical state
    /// (Infura does for Ethereum and Optimism, not for Base).
    func ethCall(to: String, data: Data, block: Int) async throws -> Data {
        let selector = data.count >= 4 ? data.prefix(4).hexString : data.hexString
        let resultData = try await call(
            to: to, data: data, label: "eth_call",
            target: "\(short(to)) \(selector) @\(block)", blockTag: "0x" + String(block, radix: 16)
        )
        log("eth_call ← \(resultData.count)B", level: .response)
        return resultData
    }

    /// Runs `calls` as one Multicall3 `aggregate3` eth_call: one request and one eth_call's
    /// credits however many sub-calls it carries. Results are in call order. With `block`, it
    /// runs against that past block's state, like `ethCall(to:data:block:)`.
    func aggregate3(_ calls: [Call3], multicall3: String, context: String, block: Int? = nil) async throws -> [Call3Result] {
        let label = "aggregate3"
        let raw = try await call(
            to: multicall3, data: ABI.encodeAggregate3(calls), label: label,
            target: "\(short(multicall3)) ×\(calls.count) \(context)\(block.map { " @\($0)" } ?? "")",
            blockTag: block.map { "0x" + String($0, radix: 16) } ?? "latest"
        )
        let results: [Call3Result]
        do {
            results = try ABI.decodeAggregate3Result(raw)
        } catch {
            log("\(label) ← \(error.localizedDescription) (\(context))", level: .error)
            throw error
        }
        guard results.count == calls.count else {
            log("\(label) ← \(results.count) results for \(calls.count) calls (\(context))", level: .error)
            throw ABI.DecodeError("aggregate3 returned \(results.count) results for \(calls.count) calls")
        }
        let failed = results.filter { !$0.success }.count
        log(
            "\(label) ← \(results.count) results\(failed > 0 ? ", \(failed) reverted" : "") (\(context))",
            level: .response
        )
        return results
    }

    private func call(
        to: String, data: Data, label: String, target: String, blockTag: String = "latest", from: String? = nil
    ) async throws -> Data {
        var tx = ["to": to, "data": "0x" + data.hexString]
        if let from { tx["from"] = from }
        return try await rpc(RPCSpec(
            method: "eth_call",
            params: [tx, blockTag],
            cost: costEthCall, maxRetries: callMaxRetries, timeout: 15, label: label,
            requestDetail: target,
            noResultDetail: ": \(target)",
            retryDetail: " \(target)",
            detectsRevert: true
        )) { raw in
            (raw as? String).map { Data(hexString: Self.stripHexPrefix($0)) ?? Data() }
        }
    }

    // MARK: - Request path

    /// What differs between RPC methods; everything else goes through `rpc(_:decode:)`.
    private struct RPCSpec {
        let method: String
        let params: [Any]
        let cost: Int
        let maxRetries: Int
        let timeout: TimeInterval
        /// Leads every log line of this call, e.g. "eth_call" or "getLogs v4".
        let label: String
        /// Logged as "<label> → <detail>" before each attempt; nil logs nothing.
        var requestDetail: String? = nil
        /// Appended to "<label> ← no result".
        var noResultDetail = ""
        /// Appended to "<label> retry n/max".
        var retryDetail = ""
        var logsErrors = true
        /// Map execution-reverted errors to `Err.reverted` so they are not retried.
        var detectsRevert = false
    }

    /// Limiter, request, HTTP/JSON-RPC error handling and the retry loop for every method.
    /// `decode` runs inside the loop: returning nil means the result has the wrong shape
    /// (`noResult`), throwing means it could not be parsed; both are retried like transport errors.
    private func rpc<T>(_ spec: RPCSpec, decode: (Any) throws -> T?) async throws -> T {
        var lastError: Error?
        for attempt in 0...spec.maxRetries {
            var providerBackoff: TimeInterval?
            do {
                try await limiter.acquire(credits: spec.cost)
                let body = try JSONSerialization.data(withJSONObject: [
                    "jsonrpc": "2.0", "method": spec.method, "params": spec.params, "id": 1
                ] as [String: Any])
                var req = URLRequest(url: rpcURL)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
                req.timeoutInterval = spec.timeout

                if let detail = spec.requestDetail {
                    log("\(spec.label) → \(detail)", level: .request)
                }

                let (data, response) = try await transport(req)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let message = Self.httpErrorMessage(status: http.statusCode, body: data)
                    providerBackoff = Self.providerBackoff(retryAfter: http.value(forHTTPHeaderField: "Retry-After"), body: data)
                    // A bare "HTTP 429" does not say why; the body and any backoff hint do.
                    let detail = http.statusCode == 429
                        ? " [\(debugBody(data))\(providerBackoff.map { ", back off \(Int($0.rounded(.up)))s" } ?? "")]"
                        : ""
                    log("\(spec.label) ← \(message)\(detail)", level: .error)
                    throw Err.rpc(message)
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    log("\(spec.label) ← bad JSON (\(debugBody(data)))", level: .error)
                    throw Err.badJSON
                }
                if let err = json["error"] as? [String: Any] {
                    let msg = err["message"] as? String ?? "unknown error"
                    providerBackoff = Self.providerBackoff(retryAfter: nil, body: data)
                    if spec.logsErrors {
                        log("\(spec.label) ← error: \(msg)", level: .error)
                    }
                    if spec.detectsRevert, Err.isRevert(code: err["code"], message: msg) {
                        throw Err.reverted(msg)
                    }
                    throw Err.rpc(msg)
                }
                guard let raw = json["result"], let result = try decode(raw) else {
                    log("\(spec.label) ← no result\(spec.noResultDetail)", level: .error)
                    throw Err.noResult
                }
                return result
            } catch {
                lastError = error
                if Self.isRateLimit(error) {
                    let lowered = await limiter.noteRateLimited(pauseFor: providerBackoff)
                    let pause = Int(await limiter.pauseRemaining.rounded(.up))
                    if let cps = lowered {
                        let cap = Int(await limiter.ceilingCreditsPerSecond)
                        log("rate limited — all requests paused \(pause)s, pace lowered to \(Int(cps)) credits/s, recovers up to \(cap)", level: .info)
                    } else {
                        log("rate limited — all requests paused \(pause)s", level: .info)
                    }
                }
                guard shouldRetry(error), attempt < spec.maxRetries else { throw error }
                let next = attempt + 1
                log("\(spec.label) retry \(next)/\(spec.maxRetries)\(spec.retryDetail) — \(Self.retryReason(error))", level: .info)
                try await sleepBeforeRetry(attempt: attempt, error: error)
            }
        }
        throw lastError ?? Err.rpc("unknown")
    }

    /// Hex quantity result (eth_blockNumber, eth_chainId, gas). A non-string is `noResult`;
    /// a string that is not hex is `badJSON`.
    private func decodeQuantity(_ raw: Any) throws -> Int? {
        guard let result = raw as? String else { return nil }
        guard let n = Int(Self.stripHexPrefix(result), radix: 16) else { throw Err.badJSON }
        return n
    }

    /// "HTTP <status>", plus the JSON-RPC error message when the body carries one
    /// (Infura puts the reason for 429/403 there, e.g. "project ID request rate exceeded").
    static func httpErrorMessage(status: Int, body: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let err = json["error"] as? [String: Any],
              let message = err["message"] as? String, !message.isEmpty
        else { return "HTTP \(status)" }
        return "HTTP \(status): \(message)"
    }

    /// Seconds the provider asks clients to wait: the `Retry-After` header (seconds), or Infura's
    /// `backoff_seconds` in the JSON-RPC error data. Capped so a bad value cannot stall the app.
    static func providerBackoff(retryAfter: String?, body: Data) -> TimeInterval? {
        var seconds: Double?
        if let header = retryAfter?.trimmingCharacters(in: .whitespaces), let value = Double(header) {
            seconds = value
        } else if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let data = (json["error"] as? [String: Any])?["data"] as? [String: Any] {
            let rate = data["rate"] as? [String: Any]
            seconds = (data["backoff_seconds"] ?? rate?["backoff_seconds"]) as? Double
        }
        guard let seconds, seconds > 0 else { return nil }
        return min(seconds, RPCCreditLimiter.maxPause)
    }

    /// The provider is throttling us: HTTP 429, or a JSON-RPC error saying so on HTTP 200.
    static func isRateLimit(_ error: Error) -> Bool {
        guard case let Err.rpc(message) = error else { return false }
        if message.hasPrefix("HTTP 429") { return true }
        let m = message.lowercased()
        return ["too many requests", "rate limit", "rate exceeded", "request rate"].contains { m.contains($0) }
    }

    /// Short reason shown in "retry n/max" log lines.
    static func retryReason(_ error: Error) -> String {
        switch error {
        case let err as Err:
            switch err {
            case .rpc(let message), .reverted(let message): return message
            case .noResult: return "no result"
            case .badJSON:  return "bad JSON"
            }
        case let urlError as URLError:
            return "network error \(urlError.code.rawValue): \(urlError.localizedDescription)"
        default:
            return error.localizedDescription
        }
    }

    private static func stripHexPrefix(_ hex: String) -> String {
        hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
    }

    // MARK: - Helpers

    private func short(_ addr: String) -> String {
        let a = addr.hasPrefix("0x") ? addr : "0x\(addr)"
        guard a.count >= 10 else { return a }
        return "\(a.prefix(6))…\(a.suffix(4))"
    }

    private func log(_ message: String, level: LogLevel) {
        Task { @MainActor in LogStore.shared.log(message, level: level) }
    }

    func shouldRetry(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        guard let rpcErr = error as? Err else { return false }
        switch rpcErr {
        case .noResult, .badJSON:
            return true
        case .reverted:
            return false
        case .rpc(let message):
            let m = message.lowercased()
            let retryableHints = [
                "timeout", "timed out", "rate", "429", "too many requests",
                "busy", "temporarily", "unavailable", "overload", "connection",
                "503", "502", "504", "econnreset", "socket hang up", "upstream"
            ]
            return retryableHints.contains { m.contains($0) }
        }
    }

    private func sleepBeforeRetry(attempt: Int, error: Error) async throws {
        let baseMs: Int
        if Self.isRateLimit(error) {
            // Stronger cooldown when provider explicitly rate-limits us.
            baseMs = 900 * (1 << attempt)
        } else {
            baseMs = 180 * (1 << attempt)
        }
        let jitterMs = Int.random(in: 0...140)
        let delayNs = UInt64(baseMs + jitterMs) * 1_000_000
        try await Task.sleep(nanoseconds: delayNs)
    }

    private func debugBody(_ data: Data, maxBytes: Int = 220) -> String {
        guard !data.isEmpty else { return "empty body" }
        let prefix = data.prefix(maxBytes)
        return String(data: prefix, encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ")
            ?? "non-utf8 \(prefix.count)B"
    }
}

/// Token bucket for the provider's credit budget. It also backs off on its own: a rate-limit
/// response halves the effective rate (down to `minThrottle` of the configured budget) and
/// empties the bucket, and the rate climbs back by `recoveryStep` every `recoveryInterval`
/// seconds without another rate limit.
actor RPCCreditLimiter {
    static let minThrottle = 0.125
    /// Longest pause a provider's backoff hint can impose.
    static let maxPause: TimeInterval = 60
    /// Every request waits this long after a rate limit that names no backoff (Infura's doesn't).
    /// Each further rate limit in the same episode doubles it, up to `maxEscalatedPause`: Infura
    /// kept refusing for ~8 s after a limit, longer than a single short pause.
    static let defaultPause: TimeInterval = 2
    static let maxEscalatedPause: TimeInterval = 30
    static let recoveryStep = 0.125
    static let recoveryInterval: TimeInterval = 15
    /// A rate limit within this long of the previous one, or of the end of the pause it caused,
    /// belongs to the same episode, which lowers the rate a single step: the retries of one
    /// request and the requests that were already waiting hit the same limit.
    static let penaltyWindow: TimeInterval = 10
    /// After a rate limit the pace recovers only to this share of the pace that hit it, so it
    /// settles below the provider's limit instead of swinging between full speed and the floor.
    static let ceilingFactor = 0.8
    /// The ceiling rises one `recoveryStep` per this long without another rate limit, so a limit
    /// that only applied for a while does not slow the rest of the session.
    static let ceilingRecoveryInterval: TimeInterval = 300

    private var creditsPerSecond: Double
    private var maxBurstCredits: Double
    private(set) var availableCredits: Double
    private var lastRefill: TimeInterval
    /// Fraction of the configured budget currently in use (minThrottle...ceiling).
    private(set) var throttle: Double = 1
    /// Highest fraction the pace recovers to (minThrottle...1); lowered by each rate limit.
    private(set) var ceiling: Double = 1
    private var lastThrottleChange: TimeInterval
    private var lastCeilingChange: TimeInterval
    private var lastRateLimit: TimeInterval = -.infinity
    /// Rate limits so far in the current episode after its first.
    private var repeatsInEpisode = 0
    /// No request starts before this time; set when the provider names a backoff.
    private var pausedUntil: TimeInterval = -.infinity
    private let now: @Sendable () -> TimeInterval

    init(
        creditsPerSecond: Double,
        maxBurstCredits: Double,
        now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.creditsPerSecond = max(1, creditsPerSecond)
        self.maxBurstCredits = max(1, maxBurstCredits)
        self.availableCredits = self.maxBurstCredits
        self.now = now
        self.lastRefill = now()
        self.lastThrottleChange = lastRefill
        self.lastCeilingChange = lastRefill
    }

    var effectiveCreditsPerSecond: Double {
        creditsPerSecond * throttle
    }

    /// The pace the limiter recovers to after rate limits.
    var ceilingCreditsPerSecond: Double {
        creditsPerSecond * ceiling
    }

    var pauseRemaining: TimeInterval {
        max(0, pausedUntil - now())
    }

    func configure(creditsPerSecond: Double, maxBurstCredits: Double) {
        refill()
        // A new budget is a new starting point; what the old one learned no longer applies.
        if max(1, creditsPerSecond) != self.creditsPerSecond { ceiling = 1 }
        self.creditsPerSecond = max(1, creditsPerSecond)
        self.maxBurstCredits = max(1, maxBurstCredits)
        availableCredits = min(availableCredits, self.maxBurstCredits)
    }

    /// Throws `CancellationError` without taking credits once the caller is cancelled, so a
    /// superseded refresh neither spins here nor spends budget the next one needs.
    func acquire(credits: Int) async throws {
        // A request larger than the bucket could never start; let it through once the bucket is full.
        let needed = min(Double(max(1, credits)), maxBurstCredits)
        while true {
            try Task.checkCancellation()
            let pause = pauseRemaining
            if pause > 0 {
                try await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                continue
            }
            refill()
            if availableCredits >= needed {
                availableCredits -= needed
                return
            }
            let deficit = needed - availableCredits
            let seconds = max(0.05, deficit / effectiveCreditsPerSecond)
            let nanos = UInt64(seconds * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanos)
        }
    }

    /// Called when the provider answered with a rate limit. Every request pauses, for the
    /// provider's backoff hint when it gives one, not only the one being retried. Returns the new
    /// effective credits/s when the rate was lowered, nil when this limit was already accounted for.
    @discardableResult
    func noteRateLimited(pauseFor backoff: TimeInterval? = nil) -> Double? {
        refill()
        let t = now()
        let newEpisode = t - max(lastRateLimit, pausedUntil) >= Self.penaltyWindow
        // Requests already in flight when the pause began answer during it; they are the same
        // limit, not a sign that the pause was too short.
        let duringPause = t < pausedUntil
        lastRateLimit = t
        if newEpisode {
            repeatsInEpisode = 0
        } else if !duringPause {
            repeatsInEpisode += 1
        }
        if newEpisode || !duringPause {
            let escalated = min(Self.defaultPause * pow(2, Double(min(repeatsInEpisode, 10))), Self.maxEscalatedPause)
            let pause = min(backoff.flatMap { $0 > 0 ? $0 : nil } ?? escalated, Self.maxPause)
            pausedUntil = max(pausedUntil, t + pause)
        }
        // Requests already waiting must not go out at the old pace, and recovery starts over.
        availableCredits = 0
        lastThrottleChange = t
        lastCeilingChange = t
        guard newEpisode else { return nil }
        ceiling = max(Self.minThrottle, min(ceiling, throttle * Self.ceilingFactor))
        guard throttle > Self.minThrottle else { return nil }
        throttle = max(Self.minThrottle, throttle / 2)
        return effectiveCreditsPerSecond
    }

    private func refill() {
        let t = now()
        recoverThrottle(at: t)
        let elapsed = max(0, t - lastRefill)
        guard elapsed > 0 else { return }
        availableCredits = min(maxBurstCredits, availableCredits + elapsed * effectiveCreditsPerSecond)
        lastRefill = t
    }

    private func recoverThrottle(at t: TimeInterval) {
        while ceiling < 1, t - lastCeilingChange >= Self.ceilingRecoveryInterval {
            ceiling = min(1, ceiling + Self.recoveryStep)
            lastCeilingChange += Self.ceilingRecoveryInterval
        }
        // Time spent paused is not time without rate limits.
        lastThrottleChange = max(lastThrottleChange, pausedUntil)
        while throttle < ceiling, t - lastThrottleChange >= Self.recoveryInterval {
            throttle = min(ceiling, throttle + Self.recoveryStep)
            lastThrottleChange += Self.recoveryInterval
        }
    }
}
