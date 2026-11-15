import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("帳號安全的翻譯(/auth/sessions、/auth/password,#338)")
struct AccountSecurityTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")

    private var repository: LiveAccountSecurityRepository {
        LiveAccountSecurityRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    @Test("登入工作階段清單:裝置名稱、client、建立與最後使用時間(Unix 秒)、這台裝置")
    func loginSessions() async throws {
        try stub.reply(status: 200, fixture: "auth-sessions.json")

        let sessions = try await repository.loginSessions()

        #expect(stub.requests.first?.httpMethod == "GET")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "auth/sessions"))
        #expect(sessions == [
            LoginSession(
                id: LoginSessionID("6ea6af58-70d1-40e5-9c6a-ef07f2506d51"), client: "ios", deviceName: "iPad · My Money App",
                createdAt: Date(timeIntervalSince1970: 1_794_716_059), lastUsedAt: Date(timeIntervalSince1970: 1_794_716_059),
                isCurrent: false
            ),
            LoginSession(
                id: LoginSessionID("fb4982ae-5d64-4f81-81de-c23c418658b2"), client: "ios", deviceName: "iPhone · My Money App",
                createdAt: Date(timeIntervalSince1970: 1_794_716_050), lastUsedAt: Date(timeIntervalSince1970: 1_794_716_050),
                isCurrent: true
            ),
        ])
    }

    @Test("登出單一裝置:DELETE /auth/sessions/:id")
    func signOutOne() async throws {
        try stub.reply(status: 200, fixture: "auth-session-delete.json")

        try await repository.signOut(LoginSessionID("6ea6af58-70d1-40e5-9c6a-ef07f2506d51"))

        #expect(stub.requests.first?.httpMethod == "DELETE")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "auth/sessions/6ea6af58-70d1-40e5-9c6a-ef07f2506d51"))
    }

    @Test("已經登出的裝置:「找不到此裝置工作階段」原樣傳遞")
    func signOutMissing() async throws {
        try stub.reply(status: 404, fixture: "auth-session-delete-not-found.json")

        await #expect(throws: RepositoryError.rejected("找不到此裝置工作階段")) {
            try await repository.signOut(LoginSessionID("6ea6af58-70d1-40e5-9c6a-ef07f2506d51"))
        }
    }

    @Test("登出其他所有裝置:DELETE /auth/sessions?scope=others")
    func signOutOthers() async throws {
        try stub.reply(status: 200, fixture: "auth-sessions-revoke-others.json")

        try await repository.signOutOtherSessions()

        #expect(stub.requests.first?.httpMethod == "DELETE")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "auth/sessions").appending(queryItems: [
            URLQueryItem(name: "scope", value: "others"),
        ]))
    }

    @Test("修改密碼:POST /auth/password {current_password, new_password},回傳後端的成功訊息")
    func changePassword() async throws {
        try stub.reply(status: 200, fixture: "auth-password-changed.json")

        let message = try await repository.changePassword(current: "old-secret", new: "new-secret")

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "auth/password"))
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["current_password": "old-secret", "new_password": "new-secret"])
        #expect(message == "密碼已更新，其他裝置已登出")
    }

    @Test("目前密碼錯誤:沒有 WWW-Authenticate 的 401 照顯示後端訊息,不登出")
    func wrongCurrentPassword() async throws {
        try stub.reply(status: 401, fixture: "auth-password-wrong-current.json")

        await #expect(throws: RepositoryError.invalidCredentials("目前密碼錯誤")) {
            _ = try await repository.changePassword(current: "wrong", new: "new-secret")
        }
        #expect(session.expirationCount == 0)
    }

    @Test("新密碼太短:「新密碼至少 6 個字元」原樣傳遞")
    func newPasswordTooShort() async throws {
        try stub.reply(status: 400, fixture: "auth-password-too-short.json")

        await #expect(throws: RepositoryError.rejected("新密碼至少 6 個字元")) {
            _ = try await repository.changePassword(current: "wrong", new: "12345")
        }
    }
}
