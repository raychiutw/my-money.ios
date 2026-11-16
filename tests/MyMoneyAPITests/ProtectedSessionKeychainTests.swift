import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Security
import Testing

/// 受生物辨識保護的 Keychain 項目(#357)。真的刷臉只能在真機上確認，這裡驗存取條件與讀取結果的翻譯。
@Suite("受生物辨識保護的 session 保存")
struct ProtectedSessionKeychainTests {
    private let session = Session(
        user: User(id: UserID("u-1"), email: "u@example.com", name: "小明"),
        tokens: SessionTokens(access: nil, refresh: "refresh-1", accessExpiresAt: nil)
    )

    @Test("只認目前錄好的生物辨識,不接受裝置密碼")
    func accessControlIsCurrentBiometryOnly() {
        #expect(KeychainSessionStorage.biometricFlags == .biometryCurrentSet)
        #expect(!KeychainSessionStorage.biometricFlags.contains(.devicePasscode))
        #expect(!KeychainSessionStorage.biometricFlags.contains(.userPresence))
    }

    @Test("刷臉通過:讀回 session")
    func successDecodesSession() throws {
        let data = try #require(KeychainSessionStorage.encode(session))

        #expect(KeychainSessionStorage.protectedLoad(status: errSecSuccess, data: data) == .success(session))
    }

    @Test("使用者取消刷臉是取消")
    func userCancelIsCancelled() {
        #expect(KeychainSessionStorage.protectedLoad(status: errSecUserCanceled, data: nil) == .cancelled)
    }

    @Test("刷臉沒通過是失敗")
    func authFailedIsFailed() {
        #expect(KeychainSessionStorage.protectedLoad(status: errSecAuthFailed, data: nil) == .failed)
    }

    @Test("找不到項目(臉部資料變更後失效)或內容解不出來:保存已失效")
    func missingOrUndecodableIsInvalidated() {
        #expect(KeychainSessionStorage.protectedLoad(status: errSecItemNotFound, data: nil) == .invalidated)
        #expect(KeychainSessionStorage.protectedLoad(status: errSecSuccess, data: Data("{}".utf8)) == .invalidated)
    }
}
