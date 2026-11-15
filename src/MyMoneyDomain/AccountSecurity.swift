import Foundation

/// 登入工作階段的 ID,由後端產生。
public struct LoginSessionID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 「帳號安全」裡的一個登入工作階段(登入裝置,CONTEXT.md「登入工作階段」)。裝置名稱由後端依 User-Agent 產生。
public struct LoginSession: Hashable, Sendable, Identifiable {
    public let id: LoginSessionID
    /// 後端的 `client_id`,例如 `ios`、`web`。
    public let client: String
    public let deviceName: String
    public let createdAt: Date
    public let lastUsedAt: Date
    /// 是不是目前這台裝置。
    public let isCurrent: Bool

    public init(id: LoginSessionID, client: String, deviceName: String, createdAt: Date, lastUsedAt: Date, isCurrent: Bool) {
        self.id = id
        self.client = client
        self.deviceName = deviceName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isCurrent = isCurrent
    }
}

/// 帳號安全(與 web 的設定頁對等,#338):登入裝置與修改密碼。passkey(#339)另有自己的 repository。
public protocol AccountSecurityRepository: Sendable {
    /// 還有效的登入工作階段,最近使用的在前(`GET /auth/sessions`)。
    func loginSessions() async throws -> [LoginSession]

    /// 登出某一台裝置(`DELETE /auth/sessions/:id`)。
    func signOut(_ id: LoginSessionID) async throws

    /// 登出這台以外的所有裝置(`DELETE /auth/sessions?scope=others`)。
    func signOutOtherSessions() async throws

    /// 修改密碼(`POST /auth/password`);後端同時登出其他裝置,這台保持登入。回傳後端的成功訊息。
    /// 目前密碼錯誤丟 `RepositoryError.invalidCredentials`(沒有 `WWW-Authenticate` 的 401)。
    func changePassword(current: String, new: String) async throws -> String
}
