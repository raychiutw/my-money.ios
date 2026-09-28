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
    }

    let baseURL: URL
    let urlSession: URLSession
    private let state = Mutex<(reply: Reply?, requests: [URLRequest])>((nil, []))

    init() {
        baseURL = URL(string: "https://\(UUID().uuidString.lowercased()).stub.test")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        urlSession = URLSession(configuration: configuration)
        StubURLProtocol.register(self, host: baseURL.host()!)
    }

    /// 之後的每個請求都回應這份 fixture。
    func reply(status: Int, fixture name: String) throws {
        let body = try Fixture.data(name)
        let contentType = name.hasSuffix(".json") ? "application/json" : "text/plain; charset=UTF-8"
        state.withLock { $0.reply = Reply(status: status, contentType: contentType, body: body) }
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
            return state.reply
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
                headerFields: ["Content-Type": reply.contentType]
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
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
}
