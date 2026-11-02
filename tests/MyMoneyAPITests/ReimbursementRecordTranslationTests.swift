import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// 撥款沖帳紀錄的編輯與刪除走 `PUT`、`DELETE /transactions/:id`(上游 ADR 0031,#314)。
/// 測試帳號不加入家庭,所以回應是照上游 `2fdc890` 的 handler 手寫的(帶 `account_id`),不是錄的 fixture。
@Suite("撥款沖帳紀錄的翻譯(/transactions/:id 與 /households/advances)")
struct ReimbursementRecordTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveHouseholdRepository {
        LiveHouseholdRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    @Test("報銷紀錄多帶 account_id(上游 2fdc890)")
    func decodesAccountID() async throws {
        stub.reply(status: 200, json: Data(#"""
        {"success":true,"data":[{"user_id":"u1","user_name":"小明","total_advanced":600,"total_reimbursed":600,"pending_reimburse":0,
        "advance_items":[],"reimbursement_items":[{"id":"r1","user_id":"u1","account_id":"acc-9","date":"2026-09-25","created_at":"2026-09-25 03:00:00","amount":600,"note":"撥款","account_name":"存款"}],
        "receiving_accounts":[],"settled_items":[]}]}
        """#.utf8))

        let advances = try await repository.advances()

        #expect(advances.first?.reimbursementItems.first?.accountID == AccountID("acc-9"))
    }

    @Test("編輯:PUT /transactions/:id,帶收款帳戶、類型 income、分類公帳代墊報銷、is_shared 0")
    func updateBody() async throws {
        stub.reply(status: 200, json: Data(#"{"success":true}"#.utf8))

        try await repository.updateReimbursement(
            TransactionID("r1"), accountID: AccountID("acc-9"), amount: Money(700), date: CalendarDay(year: 2026, month: 9, day: 26), note: "改過"
        )

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url == stub.baseURL.appending(path: "transactions/r1"))
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["account_id"] as? String == "acc-9")
        #expect(json["type"] as? String == "income")
        #expect(json["category"] as? String == "公帳代墊報銷")
        #expect(json["amount"] as? Int == 700)
        #expect(json["date"] as? String == "2026-09-26")
        #expect(json["note"] as? String == "改過")
        #expect(json["is_shared"] as? Int == 0)
    }

    @Test("刪除:DELETE /transactions/:id")
    func deleteRequest() async throws {
        stub.reply(status: 200, json: Data(#"{"success":true,"message":"已刪除"}"#.utf8))

        try await repository.deleteReimbursement(TransactionID("r1"))

        #expect(stub.requests.first?.httpMethod == "DELETE")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "transactions/r1"))
    }

    @Test("後端拒絕(400)的訊息原樣丟出")
    func rejection() async throws {
        stub.reply(status: 400, json: Data(#"{"success":false,"error":"修改後報銷金額不得低於目前已結清代墊明細合計。"}"#.utf8))

        await #expect(throws: RepositoryError.rejected("修改後報銷金額不得低於目前已結清代墊明細合計。")) {
            try await repository.updateReimbursement(
                TransactionID("r1"), accountID: AccountID("a"), amount: Money(1), date: CalendarDay(year: 2026, month: 9, day: 26), note: ""
            )
        }
    }
}
