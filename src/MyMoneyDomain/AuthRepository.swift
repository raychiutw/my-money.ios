/// 登入、註冊、登出(上游 OAuth 2.1,ADR 0038)與刪除帳號。app 不接觸密碼:帳密在系統的登入視窗(`BrowserAuthorizer`)輸入。
public protocol AuthRepository: Sendable {
    /// 開系統的登入視窗完成登入(`registering` 時直接開註冊),成功時回傳新的 session。
    /// 使用者關掉登入視窗時丟 `CancellationError`,不是錯誤。
    func signIn(registering: Bool) async throws -> Session

    /// 撤銷伺服器端的登入工作階段(`POST /oauth/revoke`)。失敗也不丟錯:本機一律照樣登出。
    func signOut(_ session: Session) async

    /// 刪除目前登入的帳號與其所有個人資料(`DELETE /auth/account`);無法復原。
    func deleteAccount() async throws
}
