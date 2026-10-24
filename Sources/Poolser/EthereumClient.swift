import Foundation

struct EthereumClient {
    /// Sends one HTTP request and returns the raw response; injectable so tests can replace the network.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let rpcURL: URL
    private let transport: Transport
    // Infura free tier nominal throughput is 500 credits/sec.
    // App default keeps a safety margin to reduce bursty 429s.
    private static let defaultBudgetCreditsPerSecond = 400
    private static let sharedLimiter = RPCCreditLimiter(
        creditsPerSecond: Double(defaultBudgetCreditsPerSecond),
        maxBurstCredits: Double(defaultBudgetCreditsPerSecond)
    )
    private let limiter: RPCCreditLimiter
    private let costEthCall = 80
    private let costEthGetLogs = 255
    private let costEthBlockNumber = 80
    private let costEthChainId = 80
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
        let cps = Double(credits)
        await sharedLimiter.configure(creditsPerSecond: cps, maxBurstCredits: cps)
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

    /// Runs `calls` as one Multicall3 `aggregate3` eth_call: one request and one eth_call's
    /// credits however many sub-calls it carries. Results are in call order.
    func aggregate3(_ calls: [Call3], multicall3: String, context: String) async throws -> [Call3Result] {
        let label = "aggregate3"
        let raw = try await call(
            to: multicall3, data: ABI.encodeAggregate3(calls), label: label,
            target: "\(short(multicall3)) ×\(calls.count) \(context)"
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

    private func call(to: String, data: Data, label: String, target: String) async throws -> Data {
        try await rpc(RPCSpec(
            method: "eth_call",
            params: [["to": to, "data": "0x" + data.hexString], "latest"],
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
                    log("\(spec.label) ← \(message)", level: .error)
                    throw Err.rpc(message)
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    log("\(spec.label) ← bad JSON (\(debugBody(data)))", level: .error)
                    throw Err.badJSON
                }
                if let err = json["error"] as? [String: Any] {
                    let msg = err["message"] as? String ?? "unknown error"
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
                if Self.isRateLimit(error), let cps = await limiter.noteRateLimited() {
                    log("rate limited — RPC pace lowered to \(Int(cps)) credits/s, recovers gradually", level: .info)
                }
                guard shouldRetry(error), attempt < spec.maxRetries else { throw error }
                let next = attempt + 1
                log("\(spec.label) retry \(next)/\(spec.maxRetries)\(spec.retryDetail) — \(Self.retryReason(error))", level: .info)
                try await sleepBeforeRetry(attempt: attempt, error: error)
            }
        }
        throw lastError ?? Err.rpc("unknown")
    }

    /// Hex quantity result (eth_blockNumber, eth_chainId). A non-string is `noResult`;
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
    static let recoveryStep = 0.125
    static let recoveryInterval: TimeInterval = 15
    /// Rate limits closer together than this count once, so one burst of parallel requests
    /// that all get HTTP 429 lowers the rate a single step.
    static let penaltyWindow: TimeInterval = 1

    private var creditsPerSecond: Double
    private var maxBurstCredits: Double
    private(set) var availableCredits: Double
    private var lastRefill: TimeInterval
    /// Fraction of the configured budget currently in use (minThrottle...1).
    private(set) var throttle: Double = 1
    private var lastThrottleChange: TimeInterval
    private var lastPenalty: TimeInterval = -.infinity
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
    }

    var effectiveCreditsPerSecond: Double {
        creditsPerSecond * throttle
    }

    func configure(creditsPerSecond: Double, maxBurstCredits: Double) {
        refill()
        self.creditsPerSecond = max(1, creditsPerSecond)
        self.maxBurstCredits = max(1, maxBurstCredits)
        availableCredits = min(availableCredits, self.maxBurstCredits)
    }

    /// Throws `CancellationError` without taking credits once the caller is cancelled, so a
    /// superseded refresh neither spins here nor spends budget the next one needs.
    func acquire(credits: Int) async throws {
        let needed = Double(max(1, credits))
        while true {
            try Task.checkCancellation()
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

    /// Called when the provider answered with a rate limit. Returns the new effective
    /// credits/s when the rate was lowered, nil when this limit was already accounted for.
    @discardableResult
    func noteRateLimited() -> Double? {
        refill()
        let t = now()
        // Requests already waiting must not go out at the old pace.
        availableCredits = 0
        guard t - lastPenalty >= Self.penaltyWindow else { return nil }
        lastPenalty = t
        guard throttle > Self.minThrottle else { return nil }
        throttle = max(Self.minThrottle, throttle / 2)
        lastThrottleChange = t
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
        while throttle < 1, t - lastThrottleChange >= Self.recoveryInterval {
            throttle = min(1, throttle + Self.recoveryStep)
            lastThrottleChange += Self.recoveryInterval
        }
    }
}
