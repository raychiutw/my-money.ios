import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("刪除帳號的翻譯(DELETE /auth/account)")
struct DeleteAccountTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider()

    private var auth: LiveAuthRepository {
        LiveAuthRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    /// 真實回應不能錄(會刪掉帳號):依後端 `backend/src/handlers/auth.ts` 的 `{success, message}` 手寫，沒有 `data`。
    @Test("DELETE /auth/account,只回 {success, message}")
    func deleteAccount() async throws {
        stub.reply(status: 200, json: Data(#"{"success":true,"message":"帳號及其所有個人資料已全數刪除"}"#.utf8))

        try await auth.deleteAccount()

        #expect(stub.requests.first?.httpMethod == "DELETE")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "auth/account"))
    }

    @Test("後端的錯誤原樣傳遞")
    func rejection() async throws {
        stub.reply(status: 404, json: Data(#"{"success":false,"error":"帳號不存在"}"#.utf8))

        await #expect(throws: RepositoryError.rejected("帳號不存在")) {
            try await auth.deleteAccount()
        }
    }
}
