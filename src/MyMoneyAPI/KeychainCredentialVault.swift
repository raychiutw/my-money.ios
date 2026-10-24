import Foundation
import MyMoneyDomain
import Security

/// 把「用 Face ID 登入」的帳密存在 Keychain(#308)。
///
/// `WhenPasscodeSetThisDeviceOnly`:裝置要設了密碼才存得進去、只留在這支裝置(不進備份、不同步 iCloud),
/// 移除裝置密碼時系統會自動刪掉。讀取前由呼叫端先用 Face ID 驗證本人。
public struct KeychainCredentialVault: CredentialVault {
    private static let account = "credentials"
    private let service: String

    /// - Parameter service: Keychain item 的 service;UI 測試不用這個(用記憶體版本)。
    public init(service: String) {
        self.service = service
    }

    public func hasSaved() -> Bool {
        var query = itemQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public func load() -> SavedCredentials? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data)
        else {
            return nil
        }
        return SavedCredentials(email: stored.email, password: stored.password)
    }

    public func save(_ credentials: SavedCredentials) {
        guard let data = try? JSONEncoder().encode(StoredCredentials(email: credentials.email, password: credentials.password)) else { return }
        delete()
        var item = itemQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        // 寫入失敗(例如沒設裝置密碼)只是下次登入不能用 Face ID,這次照常進入。
        SecItemAdd(item as CFDictionary, nil)
    }

    public func delete() {
        SecItemDelete(itemQuery as CFDictionary)
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

private struct StoredCredentials: Codable {
    let email: String
    let password: String
}
