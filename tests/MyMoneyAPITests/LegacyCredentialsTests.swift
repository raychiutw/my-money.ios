import Foundation
import MyMoneyAPI
import Security
import Testing

/// 升級後刪除「Face ID 登入」存在裝置上的帳密(#336)。
/// Keychain 本身在 `swift test` 用不了(需要 entitlement),這裡驗刪除的對象正是 0.27.0 以前存帳密的那一筆。
@Suite("刪除 Face ID 登入存的帳密")
struct LegacyCredentialsTests {
    @Test("刪除的是舊版 Face ID 登入存帳密的 Keychain 項目")
    func deletesTheSavedCredentialsItem() {
        let query = LegacyCredentials.deleteQuery

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "com.raychiu.mymoney.credentials")
        #expect(query[kSecAttrAccount as String] as? String == "credentials")
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }
}
