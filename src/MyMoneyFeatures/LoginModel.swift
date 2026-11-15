import Foundation
import MyMoneyDomain
import Observation

/// 登入頁的 model(#334):登入與註冊都在系統的登入視窗完成,app 不接觸密碼。
@MainActor
@Observable
public final class LoginModel {
    /// 上一次登入失敗的原因，照後端的訊息顯示;使用者關掉登入視窗不算失敗。
    public private(set) var errorMessage: String?

    /// 登入視窗開著，或正在用授權碼換權杖。
    public private(set) var isSubmitting = false

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let session: AppSession

    public init(auth: any AuthRepository, session: AppSession) {
        self.auth = auth
        self.session = session
    }

    /// 按「登入」:開系統的登入視窗。
    public func signIn() async {
        await authorize(registering: false)
    }

    /// 按「註冊」:開同一個登入視窗的註冊模式，註冊完直接登入。
    public func register() async {
        await authorize(registering: true)
    }

    private func authorize(registering: Bool) async {
        guard !isSubmitting else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            session.start(try await auth.signIn(registering: registering))
        } catch is CancellationError {
            // 使用者關掉登入視窗:回到登入頁，不顯示錯誤。
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
