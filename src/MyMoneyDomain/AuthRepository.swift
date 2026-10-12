/// 登入與註冊(`/auth/*`)。
public protocol AuthRepository: Sendable {
    /// 用 Email 和密碼登入，成功時回傳新的 session。
    func login(email: String, password: String) async throws -> Session

    /// 建立新帳號，成功時直接回傳登入後的 session。
    func register(name: String, email: String, password: String) async throws -> Session

    /// 刪除目前登入的帳號與其所有個人資料(`DELETE /auth/account`);無法復原。
    func deleteAccount() async throws
}
