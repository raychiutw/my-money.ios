import Foundation
import MyMoneyDomain
import Observation

/// 登入畫面的 model。
@MainActor
@Observable
public final class LoginModel {
    public var email = ""
    public var password = ""

    /// 密碼欄位是否以明碼顯示;預設隱藏。
    public var isPasswordVisible = false

    /// 上一次送出失敗的原因，照後端的訊息顯示。
    public private(set) var errorMessage: String?

    /// 正在等後端回應。
    public private(set) var isSubmitting = false

    public var submitTitle: String {
        isSubmitting ? "登入中…" : "登入"
    }

    /// Email 和密碼都是必填，兩個都填了、而且不在送出中，才能按「登入」。
    public var canSubmit: Bool {
        !isSubmitting && !trimmedEmail.isEmpty && !password.isEmpty
    }

    /// 跟 web 的 `<input type=email>` 一樣去掉前後空白。
    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let session: AppSession

    public init(auth: any AuthRepository, session: AppSession) {
        self.auth = auth
        self.session = session
    }

    /// 送出登入。
    public func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let signedIn = try await auth.login(email: trimmedEmail, password: password)
            // 清空表單：登出回來時跟 web 一樣是空白的登入頁，密碼也不留在記憶體裡。
            email = ""
            password = ""
            isPasswordVisible = false
            session.start(signedIn)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
