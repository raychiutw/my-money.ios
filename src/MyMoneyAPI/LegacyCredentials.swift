import Foundation
import Security

/// 0.27.0 以前「Face ID 登入」存在 Keychain 的帳密(#308)。登入改用系統登入視窗後不再使用,啟動時刪掉(#336)。
public enum LegacyCredentials {
    /// 沒有這一筆時 `SecItemDelete` 回 `errSecItemNotFound`,所以每次啟動都呼叫也沒關係。
    /// shortcut: 每次啟動都刪一次而不記「刪過了」,等大家都升級後(日後某一版)可以連同這個檔案拿掉。
    public static func delete() {
        SecItemDelete(deleteQuery as CFDictionary)
    }

    /// 跟當初存帳密時的 item 相同(service、account、data protection keychain)。
    package static var deleteQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.raychiu.mymoney.credentials",
            kSecAttrAccount as String: "credentials",
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
