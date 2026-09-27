import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("登入的翻譯(POST /auth/login)")
struct LoginTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider()

    private var auth: LiveAuthRepository {
        LiveAuthRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    @Test("登入成功的回應解碼成 session")
    func loginSuccessDecodesSession() async throws {
        try stub.reply(status: 200, fixture: "auth-login-success.json")

        let signedIn = try await auth.login(email: "mymoney-ios-test@example.com", password: "irrelevant")

        #expect(signedIn == Session(
            token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.ZmFrZS1maXh0dXJlLXRva2Vu.ZmFrZS1zaWduYXR1cmU",
            user: User(
                id: UserID("ff646114-6f6b-4a37-9e27-4757868af51d"),
                email: "mymoney-ios-test@example.com",
                name: "iOS 測試帳號"
            )
        ))
    }

    @Test("登入時把 Email 和密碼以 JSON 送到 POST /auth/login")
    func loginSendsCredentials() async throws {
        try stub.reply(status: 200, fixture: "auth-login-success.json")

        _ = try await auth.login(email: "mymoney-ios-test@example.com", password: "p@ss word")

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "auth/login"))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["email": "mymoney-ios-test@example.com", "password": "p@ss word"])
    }

    @Test("登入失敗時原樣傳遞後端的訊息")
    func loginFailurePassesBackendMessage() async throws {
        try stub.reply(status: 401, fixture: "auth-login-wrong-password.json")

        await #expect(throws: RepositoryError.rejected("Email 或密碼錯誤")) {
            try await auth.login(email: "mymoney-ios-test@example.com", password: "wrong-password")
        }
    }

    @Test("/auth/* 回應 401 不算 session 過期")
    func loginFailureDoesNotExpireSession() async throws {
        try stub.reply(status: 401, fixture: "auth-login-wrong-password.json")

        _ = try? await auth.login(email: "mymoney-ios-test@example.com", password: "wrong-password")

        #expect(session.expirationCount == 0)
    }
}
