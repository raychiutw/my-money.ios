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

    /// 先試更新、沒有才新增:新增失敗(例如沒設裝置密碼)時,原本可用的帳密不會被先刪掉。
    @discardableResult
    public func save(_ credentials: SavedCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(StoredCredentials(email: credentials.email, password: credentials.password)) else { return false }
        let update = SecItemUpdate(itemQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        var item = itemQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
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
