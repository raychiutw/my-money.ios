import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// 上游效能與快取(ADR 0033、0034,`86d44f2`～`ec91c31`)對 iOS 的相容性(#319)。
/// 相容性檢查不是新行為,所以沒有先紅後綠;用來擋住日後改動破壞相容。
@Suite("上游效能與快取的相容性(ETag、limit 上限、next_cursor)")
struct UpstreamPerformanceCompatTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var client: APIClient {
        APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session)
    }

    @Test("GET /transactions 多了 next_cursor 也解得出來;limit 帶 200(等於後端新上限)")
    func nextCursorIsIgnoredAndLimitIsWithinCap() async throws {
        stub.reply(status: 200, json: Data(#"{"success":true,"data":[],"next_cursor":null}"#.utf8))

        let page = try await LiveTransactionRepository(client: client).transactions(
            from: nil, to: nil, scope: .all, accountID: nil, limit: 200, offset: 0
        )

        #expect(page.isEmpty)
        let url = try #require(stub.requests.first?.url)
        let limit = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "limit" }?.value
        #expect(limit == "200")
    }

    @Test("iOS 自己不送條件式標頭(If-None-Match):304 只會由 URLSession 的快取處理,不會出現在 APIClient 面前")
    func clientNeverSendsConditionalHeaders() async throws {
        stub.reply(status: 200, json: Data(#"{"success":true,"data":[],"next_cursor":null}"#.utf8))
        let repository = LiveTransactionRepository(client: client)

        _ = try await repository.transactions(from: nil, to: nil, scope: .all, accountID: nil, limit: 20, offset: 0)
        _ = try await repository.transactions(from: nil, to: nil, scope: .all, accountID: nil, limit: 20, offset: 0)

        for request in stub.requests {
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
            #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == nil)
        }
    }

    @Test("每次查詢都是新的請求:資料變更後重抓拿得到新的內容(同一個網址連續兩次回不同資料)")
    func refetchSeesNewData() async throws {
        let repository = LiveTransactionRepository(client: client)
        stub.reply(status: 200, json: Data(#"{"success":true,"data":[],"next_cursor":null}"#.utf8))
        let before = try await repository.transactions(from: nil, to: nil, scope: .all, accountID: nil, limit: 20, offset: 0)
        try stub.reply(status: 200, fixture: "transactions-list.json")
        let after = try await repository.transactions(from: nil, to: nil, scope: .all, accountID: nil, limit: 20, offset: 0)

        #expect(before.isEmpty)
        #expect(!after.isEmpty)
    }
}
