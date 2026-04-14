import Foundation

struct EthereumClient {
    let rpcURL: URL
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
    private let callMaxRetries = 3
    private let logsMaxRetries = 4
    private let blockNumberMaxRetries = 2

    enum Err: Error, LocalizedError {
        case rpc(String)
        case noResult
        case badJSON

        var errorDescription: String? {
            switch self {
            case .rpc(let m): return "RPC: \(m)"
            case .noResult:   return "No result in RPC response"
            case .badJSON:    return "Invalid JSON from RPC"
            }
        }
    }

    func ethBlockNumber() async throws -> Int {
        var lastError: Error?
        for attempt in 0...blockNumberMaxRetries {
            do {
                await configureLimiterFromSettings()
                await Self.limiter.acquire(credits: costEthBlockNumber)
                let body = try JSONSerialization.data(withJSONObject: [
                    "jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1
                ] as [String: Any])
                var req = URLRequest(url: rpcURL)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
                req.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw Err.rpc("HTTP \(http.statusCode)")
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    log("eth_blockNumber ← bad JSON (\(debugBody(data)))", level: .error)
                    throw Err.badJSON
                }
                if let err = json["error"] as? [String: Any] {
                    throw Err.rpc(err["message"] as? String ?? "unknown")
                }
                guard let result = json["result"] as? String else {
                    log("eth_blockNumber ← no result", level: .error)
                    throw Err.noResult
                }
                let hex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
                guard let n = Int(hex, radix: 16) else { throw Err.badJSON }
                return n
            } catch {
                lastError = error
                guard shouldRetry(error), attempt < blockNumberMaxRetries else { throw error }
                let next = attempt + 1
                log("eth_blockNumber retry \(next)/\(blockNumberMaxRetries)", level: .info)
                try await sleepBeforeRetry(attempt: attempt, error: error)
            }
        }
        throw lastError ?? Err.rpc("unknown")
    }

    /// eth_getLogs query. Pass `nil` in `topics` to match any value at that position.
    func ethGetLogs(
        address: String,
        topics: [String?],
        fromBlock: String,
        toBlock: String = "latest",
        context: String? = nil
    ) async throws -> [[String: Any]] {
        let ctx = context.map { " \($0)" } ?? ""
        var lastError: Error?
        for attempt in 0...logsMaxRetries {
            do {
                await configureLimiterFromSettings()
                let jsonTopics: [Any] = topics.map { t -> Any in
                    guard let t = t else { return NSNull() }
                    return t
                }
                await Self.limiter.acquire(credits: costEthGetLogs)
                let body = try JSONSerialization.data(withJSONObject: [
                    "jsonrpc": "2.0",
                    "method":  "eth_getLogs",
                    "params":  [["address":   address,
                                 "topics":    jsonTopics,
                                 "fromBlock": fromBlock,
                                 "toBlock":   toBlock]],
                    "id":      1
                ] as [String: Any])

                var req = URLRequest(url: rpcURL)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
                req.timeoutInterval = 30

                log("getLogs\(ctx) → \(short(address)) \(fromBlock)–\(toBlock)", level: .request)

                let (responseData, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw Err.rpc("HTTP \(http.statusCode)")
                }

                guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                    log("getLogs\(ctx) ← bad JSON (\(debugBody(responseData)))", level: .error)
                    throw Err.badJSON
                }
                if let err = json["error"] as? [String: Any] {
                    let msg = err["message"] as? String ?? "unknown error"
                    log("getLogs\(ctx) ← error: \(msg)", level: .error)
                    throw Err.rpc(msg)
                }
                guard let result = json["result"] as? [[String: Any]] else {
                    log("getLogs\(ctx) ← no result (null response from RPC) \(short(address)) \(fromBlock)–\(toBlock)", level: .error)
                    throw Err.noResult
                }
                log("getLogs\(ctx) ← \(result.count) events", level: .response)
                return result
            } catch {
                lastError = error
                guard shouldRetry(error), attempt < logsMaxRetries else { throw error }
                let next = attempt + 1
                log("getLogs\(ctx) retry \(next)/\(logsMaxRetries) \(fromBlock)–\(toBlock)", level: .info)
                try await sleepBeforeRetry(attempt: attempt, error: error)
            }
        }
        throw lastError ?? Err.rpc("unknown")
    }

    func ethCall(to: String, data: Data) async throws -> Data {
        let selector = data.count >= 4 ? data.prefix(4).hexString : data.hexString
        var lastError: Error?

        for attempt in 0...callMaxRetries {
            do {
                await configureLimiterFromSettings()
                await Self.limiter.acquire(credits: costEthCall)
                let body = try JSONSerialization.data(withJSONObject: [
                    "jsonrpc": "2.0",
                    "method":  "eth_call",
                    "params":  [["to": to, "data": "0x" + data.hexString], "latest"],
                    "id":      1
                ] as [String: Any])

                var req = URLRequest(url: rpcURL)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = body
                req.timeoutInterval = 15

                log("eth_call → \(short(to)) \(selector)", level: .request)

                let (responseData, response) = try await URLSession.shared.data(for: req)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw Err.rpc("HTTP \(http.statusCode)")
                }

                guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                    log("eth_call ← bad JSON (\(debugBody(responseData)))", level: .error)
                    throw Err.badJSON
                }
                if let err = json["error"] as? [String: Any] {
                    let msg = err["message"] as? String ?? "unknown error"
                    log("eth_call ← error: \(msg)", level: .error)
                    throw Err.rpc(msg)
                }
                guard let result = json["result"] as? String else {
                    log("eth_call ← no result: \(short(to)) \(selector)", level: .error)
                    throw Err.noResult
                }

                let hex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
                let resultData = Data(hexString: hex) ?? Data()
                log("eth_call ← \(resultData.count)B", level: .response)
                return resultData
            } catch {
                lastError = error
                guard shouldRetry(error), attempt < callMaxRetries else { throw error }
                let next = attempt + 1
                log("eth_call retry \(next)/\(callMaxRetries) \(short(to)) \(selector)", level: .info)
                try await sleepBeforeRetry(attempt: attempt, error: error)
            }
        }
        throw lastError ?? Err.rpc("unknown")
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

    private func shouldRetry(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let rpcErr = error as? Err else { return false }
        switch rpcErr {
        case .noResult, .badJSON:
            return true
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

    private func configureLimiterFromSettings() async {
        let cps = Double(AppSettings.shared.rpcCreditsPerSecondBudget)
        await Self.limiter.configure(creditsPerSecond: cps, maxBurstCredits: cps)
    }
}

private actor RPCCreditLimiter {
    private var creditsPerSecond: Double
    private var maxBurstCredits: Double
    private var availableCredits: Double
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

    func acquire(credits: Int) async {
        let needed = Double(max(1, credits))
        while true {
            refill()
            if availableCredits >= needed {
                availableCredits -= needed
                return
            }
            let deficit = needed - availableCredits
            let seconds = max(0.05, deficit / creditsPerSecond)
            let nanos = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
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
