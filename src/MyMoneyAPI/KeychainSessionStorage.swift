import Foundation
import MyMoneyDomain
import Security

/// 把登入工作階段(更新權杖與登入的人)存在 Keychain;存取權杖只放記憶體(ADR-0012)。
///
/// 只在前景使用，所以用最嚴格的 `WhenUnlockedThisDeviceOnly`:裝置解鎖時才讀得到，也不會跟著備份搬到別台裝置
/// (docs/research/2026-09-28-apple-hig-ios-app.md §10.5)。
public struct KeychainSessionStorage: SessionStorage {
    private static let account = "session"
    private let service: String

    /// - Parameter service: Keychain item 的 service;UI 測試用另一個，避免碰到真的 session。
    public init(service: String) {
        self.service = service
    }

    public func load() -> Session? {
        var query = itemQuery
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

    public func save(_ session: Session) {
        guard let data = Self.encode(session) else { return }
        clear()
        var item = itemQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // 寫入失敗只影響下次開 app 要重新登入，這次的 session 照常使用。
        SecItemAdd(item as CFDictionary, nil)
    }

    public func clear() {
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
