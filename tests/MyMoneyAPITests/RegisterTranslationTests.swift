import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("註冊的翻譯(POST /auth/register)")
struct RegisterTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider()

    private var auth: LiveAuthRepository {
        LiveAuthRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    @Test("註冊時把姓名、Email 和密碼以 JSON 送到 POST /auth/register")
    func registerSendsNameEmailAndPassword() async throws {
        try stub.reply(status: 201, fixture: "auth-login-success.json")

        _ = try await auth.register(name: "iOS 測試帳號", email: "mymoney-ios-test@example.com", password: "p@ss word")

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "auth/register"))
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["name": "iOS 測試帳號", "email": "mymoney-ios-test@example.com", "password": "p@ss word"])
    }

    /// 註冊成功只能錄一次，而測試帳號的註冊回應沒錄到(見 Fixtures/README.md)。
    /// 後端 `/auth/register` 與 `/auth/login` 回傳相同的 `data`:`{token, user: {id, email, name}}`
    /// (onion523/my-money backend/src/handlers/auth.ts),所以用登入成功的真實回應代替。
    @Test("註冊成功的回應解碼成 session")
    func registerSuccessDecodesSession() async throws {
        try stub.reply(status: 201, fixture: "auth-login-success.json")

        let registered = try await auth.register(name: "iOS 測試帳號", email: "mymoney-ios-test@example.com", password: "irrelevant")

        #expect(registered.user == User(
            id: UserID("ff646114-6f6b-4a37-9e27-4757868af51d"),
            email: "mymoney-ios-test@example.com",
            name: "iOS 測試帳號"
        ))
    }

    @Test("Email 已被使用時原樣傳遞後端的訊息")
    func emailTakenPassesBackendMessage() async throws {
        try stub.reply(status: 409, fixture: "auth-register-email-taken.json")

        await #expect(throws: RepositoryError.rejected("此 Email 已被使用")) {
            try await auth.register(name: "iOS 測試帳號", email: "mymoney-ios-test@example.com", password: "irrelevant")
        }
    }
}
