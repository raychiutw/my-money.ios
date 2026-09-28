import Foundation
import MyMoneyDomain
import Observation

/// 註冊畫面的 model(parity.md「註冊」)。
@MainActor
@Observable
public final class RegisterModel {
    public var name = ""
    public var email = ""
    public var password = ""

    /// 「確認密碼」欄位。
    public var confirmation = ""

    /// 上一次送出失敗的原因：前端的檢查，或後端的訊息(例如「此 Email 已被使用」)。
    public private(set) var errorMessage: String?

    /// 正在等後端回應。
    public private(set) var isSubmitting = false

    public var submitTitle: String {
        isSubmitting ? "建立中…" : "建立帳號"
    }

    /// 四個欄位都是必填。
    public var canSubmit: Bool {
        !isSubmitting && !trimmedName.isEmpty && !trimmedEmail.isEmpty && !password.isEmpty && !confirmation.isEmpty
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let session: AppSession

    public init(auth: any AuthRepository, session: AppSession) {
        self.auth = auth
        self.session = session
    }

    /// 送出註冊。先照 web 的順序檢查兩次密碼是否一致、長度是否足夠，都通過才呼叫後端。
    public func submit() async {
        errorMessage = nil
        guard password == confirmation else {
            errorMessage = "兩次密碼不一致"
            return
        }
        // 跟 web 和後端一樣用 JavaScript 的 `length`(UTF-16 code unit)計算長度。
        guard password.utf16.count >= 6 else {
            errorMessage = "密碼至少 6 個字元"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let registered = try await auth.register(name: trimmedName, email: trimmedEmail, password: password)
            name = ""
            email = ""
            password = ""
            confirmation = ""
            session.start(registered)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
