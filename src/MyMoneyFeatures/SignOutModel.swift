import MyMoneyDomain
import Observation

/// 「我的」→ 登出(#334):清掉本機的登入狀態，並撤銷伺服器端的登入工作階段。
@MainActor
@Observable
public final class SignOutModel {
    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let session: AppSession

    public init(auth: any AuthRepository, session: AppSession) {
        self.auth = auth
        self.session = session
    }

    /// 先清掉本機(馬上回到登入頁),再撤銷伺服器端的工作階段;撤銷失敗也一樣已經登出。
    public func signOut() async {
        guard let current = session.current else { return }
        session.signOut()
        await auth.signOut(current)
    }
}
