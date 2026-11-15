import Foundation

/// 登入的人的 ID,由後端產生。
public struct UserID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 登入的人:名稱與 email 會顯示在「我的」。
public struct User: Equatable, Sendable {
    public let id: UserID
    public let email: String
    public let name: String

    public init(id: UserID, email: String, name: String) {
        self.id = id
        self.email = email
        self.name = name
    }
}

/// 登入工作階段的權杖(上游 ADR 0038)。存取權杖效期 15 分鐘、只放記憶體;更新權杖存 Keychain,用來換新的存取權杖(#335)。
public struct SessionTokens: Equatable, Sendable {
    /// 存取權杖;冷啟動從裝置讀回時是 `nil`(只放記憶體),要用更新權杖換一支新的。
    public let access: String?
    public let refresh: String
    /// 存取權杖的到期時間(收到時的 `expires_in` 換算);沒有存取權杖時是 `nil`。
    public let accessExpiresAt: Date?

    public init(access: String?, refresh: String, accessExpiresAt: Date?) {
        self.access = access
        self.refresh = refresh
        self.accessExpiresAt = accessExpiresAt
    }
}

/// 登入後的狀態:登入的人,加上這個登入工作階段的權杖。畫面 model 只看 `user`,權杖由翻譯層使用。
public struct Session: Equatable, Sendable {
    public let user: User
    public let tokens: SessionTokens

    public init(user: User, tokens: SessionTokens) {
        self.user = user
        self.tokens = tokens
    }
}
