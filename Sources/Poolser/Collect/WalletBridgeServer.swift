import Foundation
import Network
import PoolserKit

/// A short-lived HTTP server on 127.0.0.1 that serves one page to the default browser, where a
/// wallet extension can sign, and hears back what happened. It answers only under a random path,
/// only to requests addressed to 127.0.0.1 (no DNS rebinding), and stops once the page's
/// transactions are sent or after `timeout`.
final class WalletBridgeServer: @unchecked Sendable {
    /// Answers the page's `POST <path>/build` with a JSON body, or nil for a bad request.
    typealias BuildHandler = @Sendable (_ body: Data) async -> Data?

    enum Event: Equatable {
        /// Every transaction of the page is sent, hashes in order. Empty when a wallet batch
        /// did not report its hash.
        case sent(hashes: [String])
        /// Some of the page's transactions are sent and it waits for the rest.
        case partlySent(hashes: [String])
        /// The page reported a failure or a rejection; the page stays usable for another try.
        case failed(String)
        case timedOut
    }

    static let timeout: TimeInterval = 15 * 60

    // Everything below is touched only on `queue`.
    private let queue = DispatchQueue(label: "Poolser.WalletBridgeServer")
    private let listener: NWListener
    private let token = WalletBridgeServer.randomHex(bytes: 16)
    private let nonce = WalletBridgeServer.randomHex(bytes: 16)
    private let page: (_ nonce: String) -> String
    private let build: BuildHandler?
    private var port: UInt16 = 0
    private var onEvent: ((Event) -> Void)?
    private var finished = false

    init(page: @escaping (_ nonce: String) -> String, build: BuildHandler? = nil) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.acceptLocalOnly = true
        listener = try NWListener(using: parameters)
        self.page = page
        self.build = build
    }

    /// `onReady` gets the page URL once the port is bound; `onEvent` runs on a background queue.
    func start(onReady: @escaping (URL) -> Void, onEvent: @escaping (Event) -> Void) {
        queue.async { [self] in
            self.onEvent = onEvent
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    port = listener.port?.rawValue ?? 0
                    if let url = URL(string: "http://127.0.0.1:\(port)/\(token)") { onReady(url) }
                case .failed(let error):
                    finish(.failed("Local page stopped: \(error.localizedDescription)"))
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in self?.finish(.timedOut) }
        }
    }

    func stop() {
        queue.async { [self] in
            finished = true
            onEvent = nil
            listener.cancel()
        }
    }

    private func finish(_ event: Event) {
        guard !finished else { return }
        finished = true
        onEvent?(event)
        onEvent = nil
        listener.cancel()
    }

    // MARK: - HTTP

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer += data }
            if let request = HTTPRequest(buffer) {
                respond(to: request, on: connection)
            } else if isComplete || error != nil || buffer.count > 256_000 {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let origin = "127.0.0.1:\(port)"
        guard request.headers["host"] == origin else {
            return send(status: "421 Misdirected Request", on: connection)
        }
        switch (request.method, request.path) {
        case ("GET", "/\(token)"):
            send(status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(page(nonce).utf8), on: connection)
        case ("POST", "/\(token)/result"):
            guard request.headers["origin"] == "http://\(origin)" else {
                return send(status: "403 Forbidden", on: connection)
            }
            send(status: "204 No Content", on: connection)
            if let event = Self.event(fromResultBody: request.body) {
                if case .sent = event { finish(event) } else if !finished { onEvent?(event) }
            }
        case ("POST", "/\(token)/build"):
            guard request.headers["origin"] == "http://\(origin)", let build, !finished else {
                return send(status: "403 Forbidden", on: connection)
            }
            let body = request.body
            Task { [weak self] in
                let response = await build(body)
                self?.queue.async { [weak self] in
                    guard let self else { return connection.cancel() }
                    if let response {
                        send(status: "200 OK", contentType: "application/json", body: response, on: connection)
                    } else {
                        send(status: "400 Bad Request", on: connection)
                    }
                }
            }
        default:
            send(status: "404 Not Found", on: connection)
        }
    }

    private func send(status: String, contentType: String? = nil, body: Data = Data(), on connection: NWConnection) {
        var head = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        head += "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\n"
        if let contentType {
            head += "Content-Type: \(contentType)\r\n"
            head += "Content-Security-Policy: default-src 'none'; script-src 'nonce-\(nonce)'; "
                + "style-src 'nonce-\(nonce)'; img-src data:; connect-src 'self'; base-uri 'none'; form-action 'none'\r\n"
        }
        connection.send(content: Data((head + "\r\n").utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// `{"hash": "0x…"}` or `{"hashes": [...]}` once sent, with `"pending": true` while more are
    /// to come, `{"error": "…"}` otherwise; anything else is ignored.
    static func event(fromResultBody body: Data) -> Event? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        if let hash = object["hash"] as? String {
            return isHash(hash) ? .sent(hashes: [hash.lowercased()]) : nil
        }
        if let hashes = object["hashes"] as? [String] {
            guard hashes.count <= 8, hashes.allSatisfy(isHash) else { return nil }
            let lowered = hashes.map { $0.lowercased() }
            return object["pending"] as? Bool == true ? .partlySent(hashes: lowered) : .sent(hashes: lowered)
        }
        if let error = object["error"] as? String {
            return .failed(String(error.prefix(300)))
        }
        return nil
    }

    private static func isHash(_ string: String) -> Bool {
        string.count == 66 && string.hasPrefix("0x") && string.dropFirst(2).allSatisfy(\.isHexDigit)
    }

    private static func randomHex(bytes: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }
}

/// Just enough HTTP/1.1 parsing for the bridge page: request line, headers, and a body of
/// `Content-Length` bytes.
struct HTTPRequest: Equatable {
    let method: String
    let path: String
    /// Lower-cased names.
    let headers: [String: String]
    let body: Data

    /// Nil until `data` holds the whole request.
    init?(_ data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }
        method = String(requestLine[0])
        path = String(requestLine[1])
        self.headers = headers
        body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]
    }
}
