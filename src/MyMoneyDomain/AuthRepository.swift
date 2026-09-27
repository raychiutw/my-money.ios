/// 登入與註冊(`/auth/*`)。
public protocol AuthRepository: Sendable {
    /// 用 Email 和密碼登入，成功時回傳新的 session。
    func login(email: String, password: String) async throws -> Session
}
