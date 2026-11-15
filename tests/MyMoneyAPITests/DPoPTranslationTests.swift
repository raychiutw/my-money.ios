import CryptoKit
import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// DPoP 綁定(RFC 9449,上游 ADR 0039,#337):換碼、refresh 與每個受保護的請求都帶用裝置金鑰簽的 proof。
/// fixture 由 `scripts/record-oauth-fixtures.sh` 用測試帳號從 prod 錄下(錄的時候也帶 DPoP proof)。
@Suite("DPoP 綁定")
struct DPoPTranslationTests {
    private let stub = HTTPStub()
    private let keys = InMemoryDPoPKeyStore()

    private func client(_ session: FakeSessionProvider, keys: InMemoryDPoPKeyStore? = nil) -> APIClient {
        APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session, dpopKeys: keys ?? self.keys)
    }

    private static let valid = SessionTokens(access: "the-access", refresh: "stored-refresh", accessExpiresAt: .now.addingTimeInterval(600))

    /// 解開 proof,並用公鑰驗簽章(r||s,不是 DER)。
    private func proof(_ request: URLRequest?, signedBy key: P256.Signing.PublicKey?) throws -> Proof {
        let value = try #require(request?.value(forHTTPHeaderField: "DPoP"), "請求沒有 DPoP proof")
        let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        try #require(parts.count == 3)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: try #require(Self.base64URLDecode(parts[2])))
        let key = try #require(key)
        #expect(key.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)), "proof 的簽章驗不過")
        let header = try JSONSerialization.jsonObject(with: try #require(Self.base64URLDecode(parts[0]))) as? [String: Any]
        let payload = try JSONSerialization.jsonObject(with: try #require(Self.base64URLDecode(parts[1]))) as? [String: Any]
        return Proof(header: try #require(header), payload: try #require(payload))
    }

    private struct Proof {
        let header: [String: Any]
        let payload: [String: Any]
        var jwk: [String: String] { header["jwk"] as? [String: String] ?? [:] }
        var iat: Int { payload["iat"] as? Int ?? 0 }
        subscript(_ claim: String) -> String? { payload[claim] as? String }
    }

    private static func base64URLDecode(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func base64URL(_ data: some Sequence<UInt8>) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// RFC 7638 thumbprint:必要成員依字典序、沒有空白的 JSON 取 SHA-256(上游 dpop.ts 的 jwkThumbprint)。
    private static func thumbprint(_ jwk: [String: String]) -> String {
        let canonical = #"{"crv":"\#(jwk["crv"] ?? "")","kty":"\#(jwk["kty"] ?? "")","x":"\#(jwk["x"] ?? "")","y":"\#(jwk["y"] ?? "")"}"#
        return base64URL(SHA256.hash(data: Data(canonical.utf8)))
    }

    private static func thumbprint(_ key: P256.Signing.PublicKey?) -> String {
        let raw = key?.rawRepresentation ?? Data()
        return thumbprint(["kty": "EC", "crv": "P-256", "x": base64URL(raw.prefix(32)), "y": base64URL(raw.suffix(32))])
    }

    private static func httpDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    // MARK: - 換碼

    @Test("登入產生新的金鑰,換碼帶 proof:typ dpop+jwt、ES256、jwk 只有公鑰、htm POST、htu 是 token 端點、沒有 ath")
    func signInBindsNewKey() async throws {
        try stub.reply(status: 200, fixture: "oauth-token-authorization-code.json")
        let previous = Self.thumbprint(keys.publicKey)
        let auth = LiveAuthRepository(client: client(FakeSessionProvider()), browser: FakeBrowserAuthorizer(.code("the-code")))

        _ = try await auth.signIn(registering: false)

        #expect(keys.publicKey != nil)
        #expect(Self.thumbprint(keys.publicKey) != previous, "每次登入要換新的金鑰")
        let proof = try proof(stub.requests(to: "/oauth/token").first, signedBy: keys.publicKey)
        #expect(proof.header["typ"] as? String == "dpop+jwt")
        #expect(proof.header["alg"] as? String == "ES256")
        #expect(Set(proof.jwk.keys) == ["kty", "crv", "x", "y"])
        #expect(Self.thumbprint(proof.jwk) == Self.thumbprint(keys.publicKey))
        #expect(proof["htm"] == "POST")
        #expect(proof["htu"] == stub.baseURL.appending(path: "oauth/token").absoluteString)
        #expect(proof["ath"] == nil)
        #expect((proof["jti"]?.count ?? 0) >= 16)
        #expect(abs(proof.iat - Int(Date().timeIntervalSince1970)) <= 5)
    }

    @Test("換碼回 invalid_dpop_proof:依 Date 校正時鐘、重簽一次,同一個授權碼換到權杖")
    func tokenEndpointRetriesOnceAfterClockSkew() async throws {
        let serverNow = Date().addingTimeInterval(300)
        try stub.route("/oauth/token", [(400, "oauth-token-invalid-dpop-proof.json"), (200, "oauth-token-authorization-code.json")])
        stub.setHeaders(["Date": Self.httpDate(serverNow)], forFirstReplyOf: "/oauth/token")
        let auth = LiveAuthRepository(client: client(FakeSessionProvider()), browser: FakeBrowserAuthorizer(.code("the-code")))

        _ = try await auth.signIn(registering: false)

        let requests = stub.requests(to: "/oauth/token")
        #expect(requests.count == 2)
        let retried = try proof(requests.last, signedBy: keys.publicKey)
        #expect(abs(retried.iat - Int(serverNow.timeIntervalSince1970)) <= 5)
    }

    @Test("換碼重送仍是 invalid_dpop_proof:顯示錯誤,只重送一次", .timeLimit(.minutes(1)))
    func tokenEndpointRetriesOnlyOnce() async throws {
        try stub.route("/oauth/token", [(400, "oauth-token-invalid-dpop-proof.json")])
        let auth = LiveAuthRepository(client: client(FakeSessionProvider()), browser: FakeBrowserAuthorizer(.code("the-code")))

        await #expect(throws: RepositoryError.rejected("DPoP proof htu 不符")) {
            _ = try await auth.signIn(registering: false)
        }

        #expect(stub.requests(to: "/oauth/token").count == 2)
    }

    // MARK: - 受保護的請求

    @Test("受保護的請求:Authorization 是 DPoP、proof 帶 ath,htu 不含 query(CSV 匯出也一樣)")
    func protectedRequestCarriesProof() async throws {
        try stub.reply(status: 200, fixture: "export-transactions.csv")
        let repository = LiveTransactionRepository(client: client(FakeSessionProvider(tokens: Self.valid)))

        _ = try await repository.exportCSV(from: CalendarDay(year: 2026, month: 10, day: 1), to: CalendarDay(year: 2026, month: 10, day: 31))

        let request = try #require(stub.requests(to: "/export/csv").first)
        #expect(request.url?.query() != nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "DPoP the-access")
        let proof = try proof(request, signedBy: keys.publicKey)
        #expect(proof["htm"] == "GET")
        #expect(proof["htu"] == stub.baseURL.appending(path: "export/csv").absoluteString)
        #expect(proof["ath"] == Self.base64URL(SHA256.hash(data: Data("the-access".utf8))))
    }

    @Test("每個 proof 的 jti 都不一樣")
    func jtiIsUniquePerRequest() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        let client = client(FakeSessionProvider(tokens: Self.valid))

        try await client.send("DELETE", "/bot/bindings/a")
        try await client.send("DELETE", "/bot/bindings/a")

        let jtis = try stub.requests.map { try proof($0, signedBy: keys.publicKey)["jti"] }
        #expect(jtis.count == 2)
        #expect(Set(jtis).count == 2)
        #expect(try proof(stub.requests.first, signedBy: keys.publicKey)["htm"] == "DELETE")
    }

    @Test("refresh 用同一把金鑰簽 proof(後端要求跟登入時綁定的相同)")
    func refreshUsesBoundKey() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")
        try stub.route("/oauth/token", [(200, "oauth-token-refresh.json")])
        let session = FakeSessionProvider(tokens: SessionTokens(access: nil, refresh: "stored-refresh", accessExpiresAt: nil))

        try await client(session).send("DELETE", "/bot/bindings/a")

        let proof = try proof(stub.requests(to: "/oauth/token").first, signedBy: keys.publicKey)
        #expect(Self.thumbprint(proof.jwk) == Self.thumbprint(keys.publicKey))
        #expect(proof["ath"] == nil)
        let access = try #require(session.tokens?.access)
        #expect(stub.requests(to: "/bot/bindings/a").first?.value(forHTTPHeaderField: "Authorization") == "DPoP \(access)")
    }

    @Test("401 invalid_dpop_proof:依回應的 Date 算時差、重簽並重送一次,不登出")
    func invalidProofResignsOnceWithServerClock() async throws {
        let serverNow = Date().addingTimeInterval(-400)
        try stub.route("/accounts", [(401, "accounts-invalid-dpop-proof.json"), (200, "accounts-list.json")])
        stub.setHeaders(["Date": Self.httpDate(serverNow)], forFirstReplyOf: "/accounts")
        let session = FakeSessionProvider(tokens: Self.valid)

        _ = try await LiveAccountRepository(client: client(session)).accounts(scope: .all)

        let requests = stub.requests(to: "/accounts")
        #expect(requests.count == 2)
        let first = try proof(requests.first, signedBy: keys.publicKey)
        let retried = try proof(requests.last, signedBy: keys.publicKey)
        #expect(first["jti"] != retried["jti"])
        #expect(abs(retried.iat - Int(serverNow.timeIntervalSince1970)) <= 5)
        #expect(session.expirationCount == 0)
    }

    // 只重送一次的守門被拿掉時會無限重送:設時限讓它變成失敗而不是卡住。
    @Test("重送仍是 invalid_dpop_proof:顯示錯誤、不再重送,也不登出", .timeLimit(.minutes(1)))
    func invalidProofTwiceShowsErrorWithoutSignOut() async throws {
        try stub.reply(status: 401, fixture: "accounts-invalid-dpop-proof.json")
        let session = FakeSessionProvider(tokens: Self.valid)

        await #expect(throws: RepositoryError.rejected("DPoP proof htu 不符")) {
            _ = try await LiveAccountRepository(client: client(session)).accounts(scope: .all)
        }

        #expect(stub.requests(to: "/accounts").count == 2)
        #expect(session.expirationCount == 0)
        #expect(keys.publicKey != nil)
    }

    @Test("沒有金鑰時照舊用 Bearer、不帶 proof")
    func withoutKeyFallsBackToBearer() async throws {
        try stub.reply(status: 200, fixture: "bot-bindings-delete.json")

        try await client(FakeSessionProvider(tokens: Self.valid), keys: InMemoryDPoPKeyStore(hasKey: false)).send("DELETE", "/bot/bindings/a")

        #expect(stub.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer the-access")
        #expect(stub.requests.first?.value(forHTTPHeaderField: "DPoP") == nil)
    }

    // MARK: - 刪除金鑰

    @Test("refresh 回 invalid_grant:刪掉金鑰")
    func invalidGrantDeletesKey() async throws {
        try stub.route("/oauth/token", [(400, "oauth-token-refresh-invalid-grant.json")])
        let session = FakeSessionProvider(tokens: SessionTokens(access: nil, refresh: "stored-refresh", accessExpiresAt: nil))

        await #expect(throws: RepositoryError.sessionExpired) {
            try await client(session).send("DELETE", "/bot/bindings/a")
        }

        #expect(keys.publicKey == nil)
    }

    @Test("登出:撤銷之後刪掉金鑰")
    func signOutDeletesKey() async throws {
        try stub.reply(status: 200, fixture: "oauth-revoke.json")
        let auth = LiveAuthRepository(client: client(FakeSessionProvider()), browser: FakeBrowserAuthorizer(.cancelled))
        let current = Session(
            user: User(id: UserID("u"), email: "u@example.com", name: "U"),
            tokens: SessionTokens(access: "the-access", refresh: "r", accessExpiresAt: nil)
        )

        await auth.signOut(current)

        #expect(stub.requests(to: "/oauth/revoke").count == 1)
        #expect(keys.publicKey == nil)
    }

    @Test("刪除帳號成功:刪掉金鑰;失敗時保留")
    func accountDeletionDeletesKey() async throws {
        let auth = LiveAuthRepository(client: client(FakeSessionProvider(tokens: Self.valid)), browser: FakeBrowserAuthorizer(.cancelled))
        stub.reply(status: 404, json: Data(#"{"success":false,"error":"帳號不存在"}"#.utf8))
        _ = try? await auth.deleteAccount()
        #expect(keys.publicKey != nil)

        stub.reply(status: 200, json: Data(#"{"success":true,"message":"帳號及其所有個人資料已全數刪除"}"#.utf8))
        try await auth.deleteAccount()

        #expect(keys.publicKey == nil)
    }
}
