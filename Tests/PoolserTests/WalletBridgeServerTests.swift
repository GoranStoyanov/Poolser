import Foundation
import Testing
@testable import Poolser
@testable import PoolserKit

@Suite("Wallet bridge HTTP")
struct HTTPRequestTests {
    @Test func waitsForTheWholeBody() {
        let head = "POST /abc/result HTTP/1.1\r\nHost: 127.0.0.1:5\r\nContent-Length: 4\r\n\r\n"
        #expect(HTTPRequest(Data((head + "{}").utf8)) == nil)
        let request = HTTPRequest(Data((head + "{\"a\"").utf8))
        #expect(request?.method == "POST")
        #expect(request?.path == "/abc/result")
        #expect(request?.headers["host"] == "127.0.0.1:5")
        #expect(request?.body == Data("{\"a\"".utf8))
    }

    @Test func resultBodies() {
        let hash = "0x" + String(repeating: "ab", count: 32)
        #expect(WalletBridgeServer.event(fromResultBody: Data("{\"hash\":\"\(hash.uppercased().replacingOccurrences(of: "0X", with: "0x"))\"}".utf8))
                == .sent(hashes: [hash]))
        #expect(WalletBridgeServer.event(fromResultBody: Data("{\"hash\":\"0x12\"}".utf8)) == nil)
        let other = "0x" + String(repeating: "cd", count: 32)
        #expect(WalletBridgeServer.event(fromResultBody: Data("{\"hashes\":[\"\(hash)\",\"\(other)\"]}".utf8))
                == .sent(hashes: [hash, other]))
        #expect(WalletBridgeServer.event(fromResultBody: Data("{\"hashes\":[\"\(hash)\"],\"pending\":true}".utf8))
                == .partlySent(hashes: [hash]))
        #expect(WalletBridgeServer.event(fromResultBody: Data("{\"hashes\":[]}".utf8)) == .sent(hashes: []))
        #expect(WalletBridgeServer.event(fromResultBody: Data("{\"hashes\":[\"\(hash)\",\"0x12\"]}".utf8)) == nil)
        #expect(WalletBridgeServer.event(fromResultBody: Data("{\"error\":\"Cancelled\"}".utf8)) == .failed("Cancelled"))
        #expect(WalletBridgeServer.event(fromResultBody: Data("nope".utf8)) == nil)
    }
}

@Suite("Collect page")
struct CollectPageTests {
    private func request(pair sym: String = "ETH") throws -> CollectRequest {
        var pos = Position(
            chainID: "ethereum", chainName: "Ethereum", chainNumericID: 1, tokenId: "7",
            token0: "0x0", token1: "0x1", sym0: sym, sym1: "USDC", feePct: "0.05", feeRaw: 500,
            fees0: 1, fees1: 0, tickLower: 0, tickUpper: 10, liquidity: 1
        )
        pos.usd = 12
        return try #require(CollectRequest(position: pos, owner: "0x8f3c4b1e9d2a7c6f5e0b3a8d1c4e7f2a9b6da21c"))
    }

    @Test func tokenSymbolsAreEscaped() throws {
        let html = CollectPage.html(for: try request(pair: "<script>x</script>"), nonce: "n")
        #expect(!html.contains("<script>x</script>"))
        #expect(html.contains("&lt;script&gt;x&lt;/script&gt;"))
    }

    @Test func transactionJSONCannotCloseItsBlock() throws {
        let json = CollectPage.transactionJSON(try request(), explorer: "https://x/</script><b>")
        #expect(!json.contains("<"))
        #expect(!json.contains(">"))
        let decoded = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        #expect(decoded?["explorer"] as? String == "https://x/</script><b>")
        #expect(decoded?["chainId"] as? Int == 1)
    }

    @Test func logoIsInlinedAsADataURI() throws {
        let html = CollectPage.html(for: try request(), nonce: "n", logoPNG: Data([0x89, 0x50, 0x4e, 0x47]))
        #expect(html.contains("<img class=\"logo\" src=\"data:image/png;base64,iVBORw==\""))
        #expect(html.contains("<link rel=\"icon\" href=\"data:image/png;base64,iVBORw==\">"))
        #expect(CollectPage.html(for: try request(), nonce: "n").contains("logo-fallback"))
    }

    @Test func scriptsCarryTheNonce() throws {
        let html = CollectPage.html(for: try request(), nonce: "abc123")
        #expect(html.contains("<script nonce=\"abc123\">"))
        #expect(html.contains("<style nonce=\"abc123\">"))
    }
}

@Suite("Wallet bridge server")
struct WalletBridgeServerTests {
    /// Starts a server and returns its page URL plus a stream of what it reports.
    private func start(
        build: WalletBridgeServer.BuildHandler? = nil
    ) async throws -> (WalletBridgeServer, URL, AsyncStream<WalletBridgeServer.Event>) {
        let server = try WalletBridgeServer(page: { nonce in "<p>page \(nonce)</p>" }, build: build)
        let (events, continuation) = AsyncStream.makeStream(of: WalletBridgeServer.Event.self)
        let url = await withCheckedContinuation { ready in
            server.start(onReady: { ready.resume(returning: $0) }, onEvent: { continuation.yield($0) })
        }
        return (server, url, events)
    }

    @Test func servesThePageAndReportsTheHash() async throws {
        let (server, url, events) = try await start()
        defer { server.stop() }
        #expect(url.host == "127.0.0.1")

        let (page, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: page, as: UTF8.self).hasPrefix("<p>page "))
        #expect((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("script-src 'nonce-") == true)

        let hash = "0x" + String(repeating: "1f", count: 32)
        var post = URLRequest(url: url.appendingPathComponent("result"))
        post.httpMethod = "POST"
        post.setValue("http://127.0.0.1:\(url.port ?? 0)", forHTTPHeaderField: "Origin")
        post.httpBody = Data("{\"hash\":\"\(hash)\"}".utf8)
        let (_, postResponse) = try await URLSession.shared.data(for: post)
        #expect((postResponse as? HTTPURLResponse)?.statusCode == 204)

        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .sent(hashes: [hash]))
    }

    @Test func answersBuildRequestsFromThePageOnly() async throws {
        let (server, url, _) = try await start { body in
            Data("{\"echo\":".utf8) + body + Data("}".utf8)
        }
        defer { server.stop() }

        var build = URLRequest(url: url.appendingPathComponent("build"))
        build.httpMethod = "POST"
        build.setValue("http://127.0.0.1:\(url.port ?? 0)", forHTTPHeaderField: "Origin")
        build.httpBody = Data("{\"ids\":[\"a\"]}".utf8)
        let (body, response) = try await URLSession.shared.data(for: build)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(String(decoding: body, as: UTF8.self) == "{\"echo\":{\"ids\":[\"a\"]}}")

        build.setValue("https://evil.example", forHTTPHeaderField: "Origin")
        let (_, forbidden) = try await URLSession.shared.data(for: build)
        #expect((forbidden as? HTTPURLResponse)?.statusCode == 403)
    }

    @Test func noBuildEndpointForASinglePositionPage() async throws {
        let (server, url, _) = try await start()
        defer { server.stop() }
        var build = URLRequest(url: url.appendingPathComponent("build"))
        build.httpMethod = "POST"
        build.setValue("http://127.0.0.1:\(url.port ?? 0)", forHTTPHeaderField: "Origin")
        build.httpBody = Data("{}".utf8)
        let (_, response) = try await URLSession.shared.data(for: build)
        #expect((response as? HTTPURLResponse)?.statusCode == 403)
    }

    @Test func rejectsOtherPathsOriginsAndHosts() async throws {
        let (server, url, _) = try await start()
        defer { server.stop() }

        let wrongPath = url.deletingLastPathComponent().appendingPathComponent("guess")
        let (_, notFound) = try await URLSession.shared.data(from: wrongPath)
        #expect((notFound as? HTTPURLResponse)?.statusCode == 404)

        var foreign = URLRequest(url: url.appendingPathComponent("result"))
        foreign.httpMethod = "POST"
        foreign.setValue("https://evil.example", forHTTPHeaderField: "Origin")
        foreign.httpBody = Data("{\"error\":\"x\"}".utf8)
        let (_, forbidden) = try await URLSession.shared.data(for: foreign)
        #expect((forbidden as? HTTPURLResponse)?.statusCode == 403)

        // A DNS-rebound name pointing at 127.0.0.1 arrives with a different Host header.
        var rebound = URLRequest(url: url)
        rebound.setValue("evil.example:\(url.port ?? 0)", forHTTPHeaderField: "Host")
        let (_, misdirected) = try await URLSession.shared.data(for: rebound)
        #expect((misdirected as? HTTPURLResponse)?.statusCode == 421)
    }
}
