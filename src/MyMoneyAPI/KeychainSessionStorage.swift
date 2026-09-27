import Foundation
import MyMoneyDomain
import Security

/// 把 session(JWT 與登入的人)存在 Keychain。
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
        guard
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let stored = try? JSONDecoder().decode(StoredSession.self, from: data)
        else {
            return nil
        }
        return stored.session
    }

    public func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(StoredSession(session)) else { return }
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

/// Keychain 裡存的格式，只在這個檔案裡使用。
private struct StoredSession: Codable {
    let token: String
    let userID: String
    let email: String
    let name: String

    init(_ session: Session) {
        token = session.token
        userID = session.user.id.rawValue
        email = session.user.email
        name = session.user.name
    }

    var session: Session {
        Session(token: token, user: User(id: UserID(userID), email: email, name: name))
    }
}
