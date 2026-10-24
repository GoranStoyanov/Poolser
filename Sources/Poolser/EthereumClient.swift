import Foundation

struct EthereumClient {
    /// Sends one HTTP request and returns the raw response; injectable so tests can replace the network.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let rpcURL: URL
    private let transport: Transport
    // Infura free tier nominal throughput is 500 credits/sec.
    // App default keeps a safety margin to reduce bursty 429s.
    private static let defaultBudgetCreditsPerSecond = 400
    private static let limiter = RPCCreditLimiter(
        creditsPerSecond: Double(defaultBudgetCreditsPerSecond),
        maxBurstCredits: Double(defaultBudgetCreditsPerSecond)
    )
    private let costEthCall = 80
    private let costEthGetLogs = 255
    private let costEthBlockNumber = 80
    private let costEthChainId = 80
    private let callMaxRetries = 3
    private let logsMaxRetries = 4
    private let blockNumberMaxRetries = 2
    private let chainIdMaxRetries = 2

    init(rpcURL: URL, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.rpcURL = rpcURL
        self.transport = transport
    }

    /// Shared by every client. Called with a value read on the main actor at the start of a
    /// load, so request code never touches `AppSettings`.
    static func setCreditBudget(perSecond credits: Int) async {
        let cps = Double(credits)
        await limiter.configure(creditsPerSecond: cps, maxBurstCredits: cps)
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
        let target = "\(short(to)) \(selector)"
        let resultData = try await rpc(RPCSpec(
            method: "eth_call",
            params: [["to": to, "data": "0x" + data.hexString], "latest"],
            cost: costEthCall, maxRetries: callMaxRetries, timeout: 15, label: "eth_call",
            requestDetail: target,
            noResultDetail: ": \(target)",
            retryDetail: " \(target)",
            detectsRevert: true
        )) { raw in
            (raw as? String).map { Data(hexString: Self.stripHexPrefix($0)) ?? Data() }
        }
        log("eth_call ← \(resultData.count)B", level: .response)
        return resultData
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
                try await Self.limiter.acquire(credits: spec.cost)
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
                    throw Err.rpc("HTTP \(http.statusCode)")
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
                guard shouldRetry(error), attempt < spec.maxRetries else { throw error }
                let next = attempt + 1
                log("\(spec.label) retry \(next)/\(spec.maxRetries)\(spec.retryDetail)", level: .info)
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
        if case let Err.rpc(message) = error, message.contains("HTTP 429") {
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

actor RPCCreditLimiter {
    private var creditsPerSecond: Double
    private var maxBurstCredits: Double
    private(set) var availableCredits: Double
    private var lastRefill: TimeInterval

    init(creditsPerSecond: Double, maxBurstCredits: Double) {
        self.creditsPerSecond = max(1, creditsPerSecond)
        self.maxBurstCredits = max(1, maxBurstCredits)
        self.availableCredits = self.maxBurstCredits
        self.lastRefill = Date().timeIntervalSince1970
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
            let seconds = max(0.05, deficit / creditsPerSecond)
            let nanos = UInt64(seconds * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanos)
        }
    }

    private func refill() {
        let now = Date().timeIntervalSince1970
        let elapsed = max(0, now - lastRefill)
        guard elapsed > 0 else { return }
        availableCredits = min(maxBurstCredits, availableCredits + elapsed * creditsPerSecond)
        lastRefill = now
    }
}
