import Foundation
@testable import Poolser

/// A fake JSON-RPC node for eth_call. Answers from a table keyed by target and calldata, and
/// runs Multicall3 `aggregate3` against the same table, so the batched and the per-call read
/// paths can be compared on identical chain state.
actor FakeChain {
    enum Answer {
        case value(Data)
        /// Reverts with `Error(string)`; a direct eth_call reports "execution reverted: <reason>".
        case revert(String)
    }

    struct Request {
        let to: String
        let data: Data
        /// Sub-calls carried, when the request was an aggregate3.
        let subcalls: Int?
    }

    let multicall3: String
    private var answers: [String: Answer] = [:]
    /// Calls that revert with "Not approved" when Multicall3 is msg.sender, like v3 collect().
    private var senderChecked: Set<String> = []
    /// An aggregate3 with more sub-calls than this reverts as if out of gas.
    var maxSubcallsPerAggregate = Int.max
    /// Answers the next request with a JSON-RPC error that is not retried.
    private var failNextRequest: String?
    private(set) var requests: [Request] = []

    init(multicall3: String = SupportedChain.canonicalMulticall3) {
        self.multicall3 = multicall3
    }

    func set(_ target: String, _ data: Data, _ answer: Answer, checksSender: Bool = false) {
        let key = Self.key(target, data)
        answers[key] = answer
        if checksSender { senderChecked.insert(key) }
    }

    func setMaxSubcallsPerAggregate(_ max: Int) { maxSubcallsPerAggregate = max }

    func failNextRequest(with message: String) { failNextRequest = message }

    var aggregateCount: Int { requests.filter { $0.subcalls != nil }.count }

    nonisolated func client(limiter: RPCCreditLimiter = RPCCreditLimiter(creditsPerSecond: 1e9, maxBurstCredits: 1e9)) -> EthereumClient {
        EthereumClient(rpcURL: URL(string: "https://rpc.test/v3")!, limiter: limiter) { [self] request in
            try await self.handle(request)
        }
    }

    private func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let params = body["params"] as! [Any]
        let call = params[0] as! [String: String]
        let to = call["to"]!
        let data = Data(hexString: call["data"]!)!

        let reply: String
        if let message = failNextRequest {
            failNextRequest = nil
            requests.append(Request(to: to, data: data, subcalls: nil))
            reply = #""error":{"code":-32602,"message":"\#(message)"}"#
        } else if to.lowercased() == multicall3.lowercased() {
            let calls = decodeAggregate3Calls(data)
            requests.append(Request(to: to, data: data, subcalls: calls.count))
            if calls.count > maxSubcallsPerAggregate {
                reply = #""error":{"code":3,"message":"execution reverted"}"#
            } else {
                let results = calls.map { sub -> (Bool, Data) in
                    let key = Self.key(sub.target, sub.data)
                    if senderChecked.contains(key) { return (false, errorString("Not approved")) }
                    switch answers[key] ?? .revert("no fake") {
                    case .value(let value): return (true, value)
                    case .revert(let reason): return (false, errorString(reason))
                    }
                }
                reply = #""result":"0x\#(encodeAggregate3Results(results).hexString)""#
            }
        } else {
            requests.append(Request(to: to, data: data, subcalls: nil))
            switch answers[Self.key(to, data)] ?? .revert("no fake") {
            case .value(let value):
                reply = #""result":"0x\#(value.hexString)""#
            case .revert(let reason):
                reply = #""error":{"code":3,"message":"execution reverted: \#(reason)"}"#
            }
        }
        let json = #"{"jsonrpc":"2.0","id":1,\#(reply)}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }

    private static func key(_ target: String, _ data: Data) -> String {
        "\(target.lowercased()):\(data.hexString)"
    }
}

// MARK: - Independent aggregate3 codec for the fake node

func word(_ value: Int) -> Data {
    var out = Data(count: 32)
    var v = value
    for i in stride(from: 31, through: 24, by: -1) { out[i] = UInt8(v & 0xff); v >>= 8 }
    return out
}

func padded(_ data: Data) -> Data {
    data + Data(count: (32 - data.count % 32) % 32)
}

/// ABI-encoded `Error(string)` revert data.
func errorString(_ reason: String) -> Data {
    let bytes = Data(reason.utf8)
    return Data([0x08, 0xc3, 0x79, 0xa0]) + word(32) + word(bytes.count) + padded(bytes)
}

private func intWord(_ data: Data, _ offset: Int) -> Int {
    Int(data.readUInt64(wordAt: offset))
}

/// Parses aggregate3 calldata into its sub-calls.
func decodeAggregate3Calls(_ calldata: Data) -> [(target: String, allowFailure: Bool, data: Data)] {
    let body = Data(calldata.dropFirst(4))
    let array = intWord(body, 0)
    let count = intWord(body, array)
    let heads = array + 32
    return (0..<count).map { i in
        let tuple = heads + intWord(body, heads + 32 * i)
        let bytes = tuple + intWord(body, tuple + 64)
        let length = intWord(body, bytes)
        return (
            target: body.readAddress(wordAt: tuple),
            allowFailure: !body.isZeroWord(at: tuple + 32),
            data: body.subdata(in: (bytes + 32)..<(bytes + 32 + length))
        )
    }
}

/// Encodes `(bool success, bytes returnData)[]` as Multicall3 returns it.
func encodeAggregate3Results(_ results: [(success: Bool, data: Data)]) -> Data {
    let tuples = results.map { word($0.success ? 1 : 0) + word(64) + word($0.data.count) + padded($0.data) }
    var out = word(32) + word(results.count)
    var offset = 32 * results.count
    for tuple in tuples { out += word(offset); offset += tuple.count }
    return tuples.reduce(out, +)
}
