/// 登入、註冊、登出(上游 OAuth 2.1,ADR 0038)與刪除帳號。app 不接觸密碼:帳密在系統的登入視窗(`BrowserAuthorizer`)輸入。
public protocol AuthRepository: Sendable {
    /// 開系統的登入視窗完成登入(`registering` 時直接開註冊),成功時回傳新的 session 與使用者是否按了生物辨識登入。
    /// 使用者關掉登入視窗時丟 `CancellationError`,不是錯誤。
    func signIn(registering: Bool) async throws -> SignInResult

    /// 撤銷伺服器端的登入工作階段(`POST /oauth/revoke`)。失敗也不丟錯:本機一律照樣登出。
    func signOut(_ session: Session) async

    /// 用目前 session 的更新權杖換新權杖(#365):刷臉讀出受保護的 session 後、進首頁前先換一次。
    /// 透過 `SessionProvider` 通知 app:成功時 `sessionDidRefresh`(存回新權杖);更新權杖被伺服器拒絕(已失效,
    /// 或綁定的金鑰已不在裝置上)時 `sessionDidExpire`,並丟 `RepositoryError.sessionExpired`。
    /// 網路錯誤等其他失敗照一般錯誤丟出，不動 session。
    func refreshSession() async throws

    /// 刪除目前登入的帳號與其所有個人資料(`DELETE /auth/account`);無法復原。
    func deleteAccount() async throws
}

/// 系統登入視窗的登入結果(#355)。
public struct SignInResult: Sendable, Equatable {
    public var session: Session
    /// 使用者在登入網頁按的是「用 Face ID 登入」(導回網址帶 `biometric=1`),App 要接著綁定 Face ID 登入。
    public var biometric: Bool

    public init(session: Session, biometric: Bool) {
        self.session = session
        self.biometric = biometric
    }
}
