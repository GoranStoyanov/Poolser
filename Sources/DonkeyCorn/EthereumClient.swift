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

    /// eth_getLogs query. Pass `nil` in `topics` to match any value at that position.
    func ethGetLogs(address: String, topics: [String?], fromBlock: String) async throws -> [[String: Any]] {
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
                         "toBlock":   "latest"]],
            "id":      1
        ] as [String: Any])

        var req = URLRequest(url: rpcURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 30

        let (responseData, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw Err.badJSON
        }
        if let err = json["error"] as? [String: Any] {
            throw Err.rpc(err["message"] as? String ?? "unknown error")
        }
        return json["result"] as? [[String: Any]] ?? []
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

        let (responseData, _) = try await URLSession.shared.data(for: req)

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw Err.badJSON
        }
        if let err = json["error"] as? [String: Any] {
            throw Err.rpc(err["message"] as? String ?? "unknown error")
        }
        guard let result = json["result"] as? String else { throw Err.noResult }

        let hex = result.hasPrefix("0x") ? String(result.dropFirst(2)) : result
        return Data(hexString: hex) ?? Data()
    }
}
