/// 登入的人的 ID,由後端產生。
public struct UserID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 登入的人:名稱與 email 會顯示在帳號 sheet。
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

/// 登入後的狀態:後端發的 JWT(效期 30 天，沒有 refresh)加上登入的人。
public struct Session: Equatable, Sendable {
    public let token: String
    public let user: User

    public init(token: String, user: User) {
        self.token = token
        self.user = user
    }
}
