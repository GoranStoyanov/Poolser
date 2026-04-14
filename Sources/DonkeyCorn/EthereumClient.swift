import Foundation

struct EthereumClient {
    let rpcURL: URL

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
        let body = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1
        ] as [String: Any])
        var req = URLRequest(url: rpcURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Err.badJSON }
        if let err = json["error"] as? [String: Any] { throw Err.rpc(err["message"] as? String ?? "unknown") }
        guard let result = json["result"] as? String else {
            log("eth_blockNumber ← no result", level: .error)
            throw Err.noResult
        }
        let hex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
        guard let n = Int(hex, radix: 16) else { throw Err.badJSON }
        return n
    }

    /// eth_getLogs query. Pass `nil` in `topics` to match any value at that position.
    func ethGetLogs(address: String, topics: [String?], fromBlock: String, toBlock: String = "latest") async throws -> [[String: Any]] {
        let jsonTopics: [Any] = topics.map { t -> Any in
            guard let t = t else { return NSNull() }
            return t
        }
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

        log("getLogs → \(short(address)) \(fromBlock)–\(toBlock)", level: .request)

        let (responseData, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            log("getLogs ← bad JSON", level: .error)
            throw Err.badJSON
        }
        if let err = json["error"] as? [String: Any] {
            let msg = err["message"] as? String ?? "unknown error"
            log("getLogs ← error: \(msg)", level: .error)
            throw Err.rpc(msg)
        }
        guard let result = json["result"] as? [[String: Any]] else {
            log("getLogs ← no result (null response from RPC) \(short(address)) \(fromBlock)–\(toBlock)", level: .error)
            return []
        }
        log("getLogs ← \(result.count) events", level: .response)
        return result
    }

    func ethCall(to: String, data: Data) async throws -> Data {
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

        let selector = data.count >= 4 ? data.prefix(4).hexString : data.hexString
        log("eth_call → \(short(to)) \(selector)", level: .request)

        let (responseData, _) = try await URLSession.shared.data(for: req)

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            log("eth_call ← bad JSON", level: .error)
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
}
