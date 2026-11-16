import Foundation
import MyMoneyDomain
import Observation

/// 登入頁的 model(#334):登入與註冊都在系統的登入視窗完成,app 不接觸密碼。
/// 登入頁一出現就自動開登入視窗一次(#348);使用者關掉後不再自動開,按「登入」才重開。
@MainActor
@Observable
public final class LoginModel {
    /// 上一次登入失敗的原因，照後端的訊息顯示;使用者關掉登入視窗不算失敗。
    public private(set) var errorMessage: String?

    /// 登入視窗開著，或正在用授權碼換權杖。
    public private(set) var isSubmitting = false

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let session: AppSession
    @ObservationIgnored private let opensSignInOnAppear: Bool
    /// 這次停在登入頁時已經自動開過;登入成功才重設,下次登出或過期回到登入頁會再自動開。
    @ObservationIgnored private var hasAutoOpened = false

    /// - Parameter opensSignInOnAppear: UI 測試預設關掉,既有測試自己按「登入」。
    public init(auth: any AuthRepository, session: AppSession, opensSignInOnAppear: Bool = true) {
        self.auth = auth
        self.session = session
        self.opensSignInOnAppear = opensSignInOnAppear
    }

    /// 登入頁出現時:還沒自動開過就開系統的登入視窗。
    public func appeared() async {
        guard opensSignInOnAppear, !hasAutoOpened else { return }
        hasAutoOpened = true
        await signIn()
    }

    /// 按「登入」:開系統的登入視窗。
    public func signIn() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            await session.start(try await auth.signIn(registering: false))
            hasAutoOpened = false
        } catch is CancellationError {
            // 使用者關掉登入視窗:回到登入頁，不顯示錯誤。
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
