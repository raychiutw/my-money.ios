import Foundation
import LocalAuthentication
import MyMoneyDomain
import Security

/// 把登入工作階段(更新權杖與登入的人)存在 Keychain;存取權杖只放記憶體(ADR-0012)。
///
/// 兩種保護等級各用一個 Keychain 項目(account 不同),同時只會留一份(#357):
/// - 一般:只在前景使用，所以用最嚴格的 `WhenUnlockedThisDeviceOnly`:裝置解鎖時才讀得到，也不會跟著備份搬到別台裝置
///   (docs/research/2026-09-28-apple-hig-ios-app.md §10.5)。
/// - 受生物辨識保護:`WhenPasscodeSetThisDeviceOnly` 加 `SecAccessControl` 的 `.biometryCurrentSet`,
///   讀取要通過目前錄好的臉(或指紋),不接受裝置密碼;新增或更改臉部資料後項目失效。寫入與刪除不需要刷臉。
public struct KeychainSessionStorage: SessionStorage {
    private static let standardAccount = "session"
    private static let biometricAccount = "session.biometric"
    /// 「登出後保留」的記號(#364):內容是登出的人的 user id 的一般項目，跟 session 一樣存在 Keychain(重裝 app 也還在，與保存一致)。
    private static let keptAfterSignOutAccount = "session.kept-after-sign-out"
    private let service: String

    /// - Parameter service: Keychain item 的 service;UI 測試用另一個，避免碰到真的 session。
    public init(service: String) {
        self.service = service
    }

    public func storedProtection() -> SessionProtection? {
        if exists(account: Self.biometricAccount) { return .biometric }
        if exists(account: Self.standardAccount) { return .standard }
        return nil
    }

    public func load() -> Session? {
        var query = itemQuery(account: Self.standardAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        guard let session = Self.decode(data) else {
            // 舊版權杖(#334 之前):不能換成新的登入工作階段,清掉、回登入頁重新登入一次。
            clear()
            return nil
        }
        return session
    }

    public func loadProtected(reason: String) async -> ProtectedSessionLoad {
        var query = itemQuery(account: Self.biometricAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.localizedReason = reason
        query[kSecUseAuthenticationContext as String] = context
        // LAContext 不是 Sendable,但它在這裡建立、設好 reason 後就只交給背景這一次的 SecItemCopyMatching,
        // 本執行緒不再讀寫它(所有權整個移交),不會同時存取。
        let sendableQuery = query as CFDictionary
        // 讀取會等系統刷臉，放到背景，不阻塞 main thread。
        let (status, data) = await Task.detached { () -> (OSStatus, Data?) in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(sendableQuery, &result)
            return (status, result as? Data)
        }.value
        let loaded = Self.protectedLoad(status: status, data: data)
        if loaded == .invalidated { clear() }
        return loaded
    }

    public func save(_ session: Session) {
        save(session, protection: storedProtection() ?? .standard)
    }

    public func save(_ session: Session, protection: SessionProtection) {
        guard let data = Self.encode(session) else { return }
        deleteSessions()
        var item: [String: Any]
        switch protection {
        case .standard:
            item = itemQuery(account: Self.standardAccount)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .biometric:
            item = itemQuery(account: Self.biometricAccount)
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, Self.biometricFlags, nil
            ) else { return }
            item[kSecAttrAccessControl as String] = access
        }
        item[kSecValueData as String] = data
        // 寫入失敗只影響下次開 app 要重新登入，這次的 session 照常使用(綁定時會讀不回來而改用一般保存)。
        SecItemAdd(item as CFDictionary, nil)
    }

    public func clear() {
        deleteSessions()
        setKeptAfterSignOut(nil)
    }

    public func keptAfterSignOut() -> UserID? {
        var query = itemQuery(account: Self.keptAfterSignOutAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        // 舊版(#364 第一版)的記號沒有內容:仍算保留,只是認不出是誰(網頁登入一律改一般保存)。
        return UserID(String(decoding: data, as: UTF8.self))
    }

    public func setKeptAfterSignOut(_ user: UserID?) {
        var item = itemQuery(account: Self.keptAfterSignOutAccount)
        SecItemDelete(item as CFDictionary)
        guard let user else { return }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecValueData as String] = Data(user.rawValue.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    /// 刪掉兩種保存(不動「登出後保留」的記號)。
    private func deleteSessions() {
        SecItemDelete(itemQuery(account: Self.standardAccount) as CFDictionary)
        SecItemDelete(itemQuery(account: Self.biometricAccount) as CFDictionary)
    }

    /// 只查屬性、不讀內容，而且不准跳刷臉:受保護的項目在也不會跳出提示。
    private func exists(account: String) -> Bool {
        var query = itemQuery(account: account)
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecReturnAttributes as String] = true
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private func itemQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

extension KeychainSessionStorage {
    /// 受保護項目的存取條件：只認目前錄好的生物辨識，不接受裝置密碼。
    package static let biometricFlags: SecAccessControlCreateFlags = .biometryCurrentSet

    /// 把 Keychain 讀取的結果翻成 domain 的讀取結果。
    package static func protectedLoad(status: OSStatus, data: Data?) -> ProtectedSessionLoad {
        switch status {
        case errSecSuccess:
            // 內容解不出來(不該發生):當作失效，清掉重新登入。
            guard let data, let session = decode(data) else { return .invalidated }
            return .success(session)
        case errSecUserCanceled: return .cancelled
        // `.biometryCurrentSet` 的項目在臉部資料變更後讀不到。
        case errSecItemNotFound: return .invalidated
        default: return .failed
        }
    }
}

/// Keychain 裡存的格式:只有更新權杖與使用者(存取權杖只放記憶體,#334)。
/// 舊版(0.27.0 以前)存的是 `{token, userID, email, name}`,沒有 `refreshToken`,解不出來。
private struct StoredSession: Codable {
    let refreshToken: String
    let userID: String
    let email: String
    let name: String
}

extension KeychainSessionStorage {
    package static func encode(_ session: Session) -> Data? {
        try? JSONEncoder().encode(StoredSession(
            refreshToken: session.tokens.refresh, userID: session.user.id.rawValue,
            email: session.user.email, name: session.user.name
        ))
    }

    /// 解不出來(例如舊版權杖)時是 `nil`。
    package static func decode(_ data: Data) -> Session? {
        guard let stored = try? JSONDecoder().decode(StoredSession.self, from: data) else { return nil }
        return Session(
            user: User(id: UserID(stored.userID), email: stored.email, name: stored.name),
            tokens: SessionTokens(access: nil, refresh: stored.refreshToken, accessExpiresAt: nil)
        )
    }
}
