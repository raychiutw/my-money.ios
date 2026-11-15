import Foundation
import Synchronization
import Testing

/// Seam 2 的 HTTP 邊界：用 `URLProtocol` 攔截 `APIClient` 送出的請求，回應從 prod 錄下的 fixture。
///
/// 每個 stub 有自己的 host,Swift Testing 平行跑測試時不會互相干擾。
final class HTTPStub: Sendable {
    struct Reply: Sendable {
        let status: Int
        let contentType: String
        let body: Data
        var headers: [String: String] = [:]
        /// 延遲多久才回應(讓並行的請求真的重疊)。
        var delay: TimeInterval = 0
    }

    let baseURL: URL
    let urlSession: URLSession
    /// `routes`:指定路徑依序回應(用完停在最後一個);`nil` 是網路錯誤。其他路徑回應 `reply`。
    private let state = Mutex<(reply: Reply?, routes: [String: [Reply?]], requests: [URLRequest])>((nil, [:], []))

    init() {
        baseURL = URL(string: "https://\(UUID().uuidString.lowercased()).stub.test")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        urlSession = URLSession(configuration: configuration)
        StubURLProtocol.register(self, host: baseURL.host()!)
    }

    /// 之後的每個請求都回應這份 fixture,連同錄下的回應標頭(`<fixture>.headers`,有的話)。
    /// `headers` 只用在 prod 錄不到的標頭(例如還沒有 DPoP 權杖時的 `invalid_dpop_proof`),會蓋過錄下的值。
    func reply(status: Int, fixture name: String, headers overrides: [String: String] = [:]) throws {
        let reply = try Self.reply(status: status, fixture: name, headers: overrides)
        state.withLock { $0.reply = reply }
    }

    /// 這個路徑的請求依序回應這些 fixture(`nil` 是網路錯誤),用完之後一直回應最後一個;優先於 `reply(status:fixture:)`。
    func route(_ path: String, _ replies: [(status: Int, fixture: String)?], delay: TimeInterval = 0) throws {
        let built: [Reply?] = try replies.map { item in
            guard let item else { return nil }
            var reply = try Self.reply(status: item.status, fixture: item.fixture, headers: [:])
            reply.delay = delay
            return reply
        }
        state.withLock { $0.routes[path] = built }
    }

    /// 這個路徑的第一個回應另外加上標頭(例如 prod 錄不到固定值的 `Date`)。
    func setHeaders(_ headers: [String: String], forFirstReplyOf path: String) {
        state.withLock { state in
            guard var first = state.routes[path]?.first ?? nil else { return }
            first.headers.merge(headers) { _, new in new }
            state.routes[path]?[0] = first
        }
    }

    private static func reply(status: Int, fixture name: String, headers overrides: [String: String]) throws -> Reply {
        let body = try Fixture.data(name)
        let contentType = name.hasSuffix(".json") ? "application/json" : "text/plain; charset=UTF-8"
        let headers = Fixture.headers(name).merging(overrides) { _, override in override }
        return Reply(status: status, contentType: contentType, body: body, headers: headers)
    }

    /// 某個路徑收到的請求。
    func requests(to path: String) -> [URLRequest] {
        requests.filter { $0.url?.path() == path }
    }

    /// 之後的每個請求都回應這份 JSON。只用在「把真實 fixture 改一個欄位」的測試，例如後端將來新增的帳戶類型。
    func reply(status: Int, json body: Data) {
        state.withLock { $0.reply = Reply(status: status, contentType: "application/json", body: body) }
    }

    /// 到目前為止收到的請求(body 已從 stream 讀回 `httpBody`)。
    var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    fileprivate func handle(_ request: URLRequest) -> Reply? {
        state.withLock { state in
            state.requests.append(request)
            guard let path = request.url?.path(), var queue = state.routes[path], let first = queue.first else {
                return state.reply
            }
            if queue.count > 1 {
                queue.removeFirst()
                state.routes[path] = queue
            }
            return first
        }
    }
}

private final class StubURLProtocol: URLProtocol {
    private static let stubs = Mutex<[String: HTTPStub]>([:])

    static func register(_ stub: HTTPStub, host: String) {
        stubs.withLock { $0[host] = stub }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var received = request
        received.httpBody = Self.readBody(of: request)
        let host = request.url?.host() ?? ""
        guard
            let stub = Self.stubs.withLock({ $0[host] }),
            let reply = stub.handle(received),
            let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: reply.status,
                httpVersion: "HTTP/2",
                headerFields: reply.headers.merging(["Content-Type": reply.contentType]) { _, type in type }
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        guard reply.delay > 0 else {
            finish(response, body: reply.body)
            return
        }
        // URLProtocol 不是 Sendable;延遲只在測試裡用,client 的回呼本來就允許在別的 thread 呼叫。
        nonisolated(unsafe) let this = self
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) {
            this.finish(response, body: reply.body)
        }
    }

    private func finish(_ response: HTTPURLResponse, body: Data) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession 交給 URLProtocol 時會把 body 換成 stream,這裡讀回來方便測試比對。
    private static func readBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// 讀取 `Fixtures/` 裡從 prod 錄下的真實回應(錄製流程見 Fixtures/README.md)。
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
            "找不到 fixture \(name)"
        )
        return try Data(contentsOf: url)
    }

    /// `scripts/record-fixture.sh` 另存的回應標頭(每行 `Name: value`);沒有這個檔就是空的。
    static func headers(_ name: String) -> [String: String] {
        guard
            let url = Bundle.module.url(forResource: name + ".headers", withExtension: nil, subdirectory: "Fixtures"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [:] }
        var headers: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return headers
    }
}
