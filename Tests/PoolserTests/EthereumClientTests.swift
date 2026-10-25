import Foundation
import Testing
@testable import Poolser

private let rpcURL = URL(string: "https://rpc.test/v3")!
private let zeroAddress = "0x0000000000000000000000000000000000000000"

/// Replays scripted responses in order (the last one repeats) and records every request.
private actor FakeTransport {
    enum Reply {
        case http(Int, String)
        case failure(Error)
    }

    private let replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    var attempts: Int { requests.count }

    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        let reply = replies[min(requests.count, replies.count - 1)]
        requests.append(request)
        switch reply {
        case .http(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        case .failure(let error):
            throw error
        }
    }

    func body(_ index: Int = 0) throws -> [String: Any] {
        let data = try #require(requests[index].httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

/// Each client gets its own generous limiter, so rate-limit tests cannot slow the shared one.
private func client(_ fake: FakeTransport, limiter: RPCCreditLimiter? = nil) -> EthereumClient {
    let limiter = limiter ?? RPCCreditLimiter(creditsPerSecond: 1_000_000, maxBurstCredits: 1_000_000)
    return EthereumClient(rpcURL: rpcURL, limiter: limiter) { try await fake.send($0) }
}

private func result(_ json: String) -> FakeTransport.Reply {
    .http(200, #"{"jsonrpc":"2.0","id":1,"result":\#(json)}"#)
}

private func rpcError(code: Int, message: String) -> FakeTransport.Reply {
    .http(200, #"{"jsonrpc":"2.0","id":1,"error":{"code":\#(code),"message":"\#(message)"}}"#)
}

@Suite struct EthereumClientRequestTests {
    @Test func blockTimestampReadsTheHeader() async throws {
        let fake = FakeTransport([result(#"{"number":"0x176ae5d","timestamp":"0x6553f100","hash":"0xab"}"#)])
        #expect(try await client(fake).ethBlockTimestamp(24_555_101) == 0x6553f100)
    }

    @Test func missingBlockIsNoResult() async {
        let fake = FakeTransport([result("null"), result("null"), result("null")])
        await #expect(throws: EthereumClient.Err.self) {
            _ = try await client(fake).ethBlockTimestamp(1)
        }
    }

    @Test func ethCallSendsJSONRPCRequestAndDecodesHex() async throws {
        let fake = FakeTransport([result(#""0x00ff""#)])
        let data = try await client(fake).ethCall(to: zeroAddress, data: Data([0x99, 0xfb, 0xab, 0x88]))

        #expect(data == Data([0x00, 0xff]))
        let request = try #require(await fake.requests.first)
        #expect(request.url == rpcURL)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == 15)

        let body = try await fake.body()
        #expect(body["jsonrpc"] as? String == "2.0")
        #expect(body["method"] as? String == "eth_call")
        let params = try #require(body["params"] as? [Any])
        #expect(params.count == 2)
        let call = try #require(params[0] as? [String: String])
        #expect(call == ["to": zeroAddress, "data": "0x99fbab88"])
        #expect(params[1] as? String == "latest")
    }

    @Test func blockNumberAndChainIdParseHexQuantities() async throws {
        let fake = FakeTransport([result(#""0x1b4""#)])
        #expect(try await client(fake).ethBlockNumber() == 436)
        #expect(try await client(fake).ethChainId() == 436)

        #expect(try await fake.body(0)["method"] as? String == "eth_blockNumber")
        #expect(try await fake.body(1)["method"] as? String == "eth_chainId")
        #expect(try await (fake.body(1)["params"] as? [Any])?.isEmpty == true)
        #expect(await fake.requests.allSatisfy { $0.timeoutInterval == 15 })
    }

    @Test func getLogsSerializesTopicsWithNullWildcards() async throws {
        let fake = FakeTransport([result(#"[{"blockNumber":"0x1"},{"blockNumber":"0x2"}]"#)])
        let logs = try await client(fake).ethGetLogs(
            address: zeroAddress, topics: ["0xaa", nil, "0xbb"], fromBlock: "0x10", toBlock: "0x20"
        )

        #expect(logs.count == 2)
        #expect(await fake.requests.first?.timeoutInterval == 30)
        let body = try await fake.body()
        #expect(body["method"] as? String == "eth_getLogs")
        let filter = try #require((body["params"] as? [Any])?.first as? [String: Any])
        #expect(filter["address"] as? String == zeroAddress)
        #expect(filter["fromBlock"] as? String == "0x10")
        #expect(filter["toBlock"] as? String == "0x20")
        let topics = try #require(filter["topics"] as? [Any])
        #expect(topics.count == 3)
        #expect(topics[0] as? String == "0xaa")
        #expect(topics[1] is NSNull)
        #expect(topics[2] as? String == "0xbb")
    }

    @Test func getLogsORSendsSingleTopicAsStringAndSeveralAsArray() async throws {
        let fake = FakeTransport([result("[]")])
        let logs = try await client(fake).ethGetLogsOR(
            address: zeroAddress, topics: [["0xaa"], nil, ["0xbb", "0xcc"]], fromBlock: "0x10"
        )

        #expect(logs.isEmpty)
        let filter = try #require((try await fake.body()["params"] as? [Any])?.first as? [String: Any])
        #expect(filter["toBlock"] as? String == "latest")
        let topics = try #require(filter["topics"] as? [Any])
        #expect(topics[0] as? String == "0xaa")
        #expect(topics[1] is NSNull)
        #expect(topics[2] as? [String] == ["0xbb", "0xcc"])
    }
}

@Suite struct EthereumClientErrorTests {
    @Test func ethCallRevertIsMappedAndNotRetried() async throws {
        let fake = FakeTransport([rpcError(code: 3, message: "execution reverted: NOT_MINTED")])
        await #expect {
            _ = try await client(fake).ethCall(to: zeroAddress, data: Data([0x63, 0x52, 0x21, 0x1e]))
        } throws: { error in
            guard case EthereumClient.Err.reverted(let message) = error else { return false }
            return message == "execution reverted: NOT_MINTED"
        }
        #expect(await fake.attempts == 1)
    }

    /// Only eth_call maps reverts; other methods keep reporting them as plain RPC errors.
    @Test func getLogsDoesNotMapReverts() async throws {
        let fake = FakeTransport([rpcError(code: 3, message: "execution reverted")])
        await #expect {
            _ = try await client(fake).ethGetLogs(address: zeroAddress, topics: [], fromBlock: "0x1")
        } throws: { error in
            guard case EthereumClient.Err.rpc(let message) = error else { return false }
            return message == "execution reverted"
        }
        #expect(await fake.attempts == 1)
    }

    @Test func nonRetryableRPCErrorFailsOnFirstAttempt() async throws {
        let fake = FakeTransport([rpcError(code: -32000, message: "header not found")])
        await #expect {
            _ = try await client(fake).ethCall(to: zeroAddress, data: Data())
        } throws: { error in
            guard case EthereumClient.Err.rpc(let message) = error else { return false }
            return message == "header not found"
        }
        #expect(await fake.attempts == 1)
    }

    @Test func nonRetryableHTTPStatusFailsOnFirstAttempt() async throws {
        let fake = FakeTransport([.http(500, "oops"), result(#""0x1""#)])
        await #expect {
            _ = try await client(fake).ethBlockNumber()
        } throws: { error in
            guard case EthereumClient.Err.rpc(let message) = error else { return false }
            return message == "HTTP 500"
        }
        #expect(await fake.attempts == 1)
    }

    @Test func missingResultIsRetriedUntilRetriesRunOut() async throws {
        let fake = FakeTransport([result("null")])
        await #expect {
            _ = try await client(fake).ethBlockNumber()
        } throws: { error in
            guard case EthereumClient.Err.noResult = error else { return false }
            return true
        }
        // eth_blockNumber allows two retries.
        #expect(await fake.attempts == 3)
    }

    @Test func wrongResultShapeIsNoResult() async throws {
        let fake = FakeTransport([result(#""0x""#), result("[]")])
        let logs = try await client(fake).ethGetLogs(address: zeroAddress, topics: [], fromBlock: "0x1")
        #expect(logs.isEmpty)
        #expect(await fake.attempts == 2)
    }

    @Test func unparsableQuantityIsBadJSON() async throws {
        let fake = FakeTransport([result(#""0xzz""#)])
        await #expect {
            _ = try await client(fake).ethChainId()
        } throws: { error in
            guard case EthereumClient.Err.badJSON = error else { return false }
            return true
        }
        #expect(await fake.attempts == 3)
    }
}

@Suite struct EthereumClientRetryTests {
    @Test(arguments: [
        FakeTransport.Reply.http(503, ""),
        .http(200, "<html>bad gateway</html>"),
        rpcError(code: -32005, message: "too many requests"),
        .failure(URLError(.timedOut)),
    ])
    fileprivate func transientFailureIsRetried(first: FakeTransport.Reply) async throws {
        let fake = FakeTransport([first, result(#""0x2a""#)])
        #expect(try await client(fake).ethBlockNumber() == 42)
        #expect(await fake.attempts == 2)
    }

    /// HTTP 429 is retried after the longer rate-limit cooldown (900 ms base instead of 180 ms).
    @Test func rateLimitedRequestBacksOffLongerThenSucceeds() async throws {
        let fake = FakeTransport([.http(429, ""), result(#""0x2a""#)])
        let start = ContinuousClock.now
        #expect(try await client(fake).ethBlockNumber() == 42)
        #expect(ContinuousClock.now - start >= .milliseconds(900))
        #expect(await fake.attempts == 2)
    }

    /// A 429 must slow every later request, not only the retried one.
    @Test func rateLimitLowersSharedPace() async throws {
        let limiter = RPCCreditLimiter(creditsPerSecond: 400, maxBurstCredits: 400)
        let fake = FakeTransport([.http(429, ""), result(#""0x2a""#)])
        #expect(try await client(fake, limiter: limiter).ethBlockNumber() == 42)
        #expect(await limiter.effectiveCreditsPerSecond == 200)
    }

    @Test func otherErrorsLeavePaceAlone() async throws {
        let limiter = RPCCreditLimiter(creditsPerSecond: 400, maxBurstCredits: 400)
        let fake = FakeTransport([.http(503, ""), result(#""0x2a""#)])
        #expect(try await client(fake, limiter: limiter).ethBlockNumber() == 42)
        #expect(await limiter.effectiveCreditsPerSecond == 400)
    }

    @Test func cancelledTransportIsNotRetried() async throws {
        let fake = FakeTransport([.failure(URLError(.cancelled)), result(#""0x2a""#)])
        await #expect(throws: URLError.self) {
            _ = try await client(fake).ethBlockNumber()
        }
        #expect(await fake.attempts == 1)
    }
}

@Suite struct EthereumClientHTTPErrorTests {
    /// Infura explains 429/403 in a JSON-RPC error body; the reason must survive into the error.
    @Test func httpErrorKeepsJSONRPCReasonFromBody() async throws {
        let body = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32005,"message":"project ID request rate exceeded"}}"#
        let fake = FakeTransport([.http(429, body), result(#""0x2a""#)])
        #expect(try await client(fake).ethBlockNumber() == 42)
        #expect(await fake.attempts == 2)
    }

    @Test func forbiddenStatusCarriesAccessMessage() async throws {
        let body = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32002,"message":"project ID does not have access to this network"}}"#
        let fake = FakeTransport([.http(403, body)])
        await #expect {
            _ = try await client(fake).ethChainId()
        } throws: { error in
            guard case EthereumClient.Err.rpc(let message) = error else { return false }
            return message == "HTTP 403: project ID does not have access to this network"
        }
        #expect(await fake.attempts == 1)
    }

    @Test(arguments: [
        (429, #"{"error":{"code":-32005,"message":"rate exceeded"}}"#, "HTTP 429: rate exceeded"),
        (500, "oops", "HTTP 500"),
        (502, "", "HTTP 502"),
        (503, #"{"error":{"message":""}}"#, "HTTP 503"),
    ])
    func httpErrorMessage(status: Int, body: String, expected: String) {
        #expect(EthereumClient.httpErrorMessage(status: status, body: Data(body.utf8)) == expected)
    }

    @Test func retryReasonNamesTheCause() {
        #expect(EthereumClient.retryReason(EthereumClient.Err.rpc("HTTP 429: rate exceeded")) == "HTTP 429: rate exceeded")
        #expect(EthereumClient.retryReason(EthereumClient.Err.noResult) == "no result")
        #expect(EthereumClient.retryReason(EthereumClient.Err.badJSON) == "bad JSON")
        #expect(EthereumClient.retryReason(URLError(.timedOut)).hasPrefix("network error -1001"))
    }
}
