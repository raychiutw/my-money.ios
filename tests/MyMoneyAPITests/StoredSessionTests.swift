import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

/// Keychain 裡存的登入工作階段(#334):只存更新權杖與使用者,存取權杖只放記憶體;舊版權杖讀不回來(要清掉、重新登入)。
/// Keychain 本身在 `swift test` 用不了(需要 entitlement),這裡只驗存進去的內容。
@Suite("裝置上保存的登入工作階段")
struct StoredSessionTests {
    private let user = User(id: UserID("u-1"), email: "u@example.com", name: "小明")

    @Test("存進裝置的內容不含存取權杖;讀回來只有更新權杖與使用者")
    func accessTokenStaysInMemory() throws {
        let session = Session(
            user: user,
            tokens: SessionTokens(access: "secret-access-token", refresh: "refresh-1", accessExpiresAt: Date())
        )

        let data = try #require(KeychainSessionStorage.encode(session))

        #expect(!String(decoding: data, as: UTF8.self).contains("secret-access-token"))
        #expect(KeychainSessionStorage.decode(data) == Session(
            user: user, tokens: SessionTokens(access: nil, refresh: "refresh-1", accessExpiresAt: nil)
        ))
    }

    @Test("舊版權杖(只有 token、沒有更新權杖)讀不回 session")
    func legacyTokenIsNotASession() {
        // 0.27.0 之前 KeychainSessionStorage 存的格式。
        let legacy = Data(#"{"token":"eyJ.legacy.jwt","userID":"u-1","email":"u@example.com","name":"小明"}"#.utf8)

        #expect(KeychainSessionStorage.decode(legacy) == nil)
    }
}
