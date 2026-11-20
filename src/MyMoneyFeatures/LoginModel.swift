import Foundation
import MyMoneyDomain
import Observation

/// 未登入時的 model(#334、#356):App 沒有自己的登入頁，登入與註冊都在系統的登入視窗完成,app 不接觸密碼。
/// 未登入就自動開登入視窗;使用者關掉就再開(沒登入什麼都不能做;主動登出後從登入入口頁開的例外，關掉回到入口頁,#367),但只在 scene 在前景時，避免在背景連續重開(#351);其他錯誤停住、顯示訊息，按「重試」才再開。
@MainActor
@Observable
public final class LoginModel {
    /// 上一次登入失敗的原因，照後端的訊息顯示;使用者關掉登入視窗不算失敗。
    public private(set) var errorMessage: String?

    /// 登入視窗開著，或正在用授權碼換權杖。
    public private(set) var isSubmitting = false

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let session: AppSession
    /// scene 在前景(scenePhase `.active`):關掉登入視窗後只有這時才再開。
    @ObservationIgnored private var isSceneActive = false

    public init(auth: any AuthRepository, session: AppSession) {
        self.auth = auth
        self.session = session
    }

    /// 未登入的畫面出現、或回到前景時:開系統的登入視窗。錯誤停住時不自動開，等使用者按「重試」。
    public func appeared() async {
        isSceneActive = true
        guard errorMessage == nil else { return }
        await signIn()
    }

    /// scene 離開前景:之後關掉的登入視窗不再開，等回到前景(`appeared()`)。
    public func sceneLeftForeground() {
        isSceneActive = false
    }

    /// 刷臉讀出受保護的 session(冷啟動或登入入口頁按「登入」),通過後先用這裡的 `auth` 換新權杖再進首頁(#365)。
    public func unlockProtectedSession() async {
        await session.unlockProtectedSession(refreshingWith: auth)
    }

    /// 按「重試」:清掉錯誤，再開系統的登入視窗。
    public func retry() async {
        errorMessage = nil
        await signIn()
    }

    private func signIn() async {
        guard !isSubmitting, session.current == nil else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        while isSceneActive, !Task.isCancelled {
            do {
                await session.start(try await auth.signIn(registering: false))
                return
            } catch is CancellationError {
                // 使用者關掉登入視窗:不是錯誤。主動登出後從入口頁開的就回到入口頁(#367);其他情況在前景就再開一次。
                if session.returnToSignInEntryIfSignedOut() { return }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
    }
}
