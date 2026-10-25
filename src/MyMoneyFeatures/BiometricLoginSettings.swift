import MyMoneyDomain
import Observation

/// 「我的」的 Face ID 登入開關(#310):開啟要重新輸入帳密、驗證成功且是目前登入的帳號才綁定;關閉就清掉已存帳密。
@MainActor
@Observable
public final class BiometricLoginSettings {
    /// 目前登入的帳號已經綁定。
    public private(set) var isEnabled = false
    /// 這支裝置能不能用 Face ID(或裝置密碼)驗證;不能就不能開啟。
    public private(set) var canEnable = false
    public private(set) var methodName = "Face ID"
    public private(set) var errorMessage: String?
    public private(set) var isWorking = false

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let session: AppSession
    @ObservationIgnored private let biometric: BiometricLogin

    public init(auth: any AuthRepository, session: AppSession, biometricLogin: BiometricLogin) {
        self.auth = auth
        self.session = session
        biometric = biometricLogin
    }

    /// 開綁定表單時預填的 Email:目前登入的帳號。
    public var currentEmail: String { session.current?.user.email ?? "" }

    public func refresh() async {
        // 先同步算開關(換帳號、登出後不會先閃出上一個帳號的狀態);沒有目前帳號就不可能是開啟。
        isEnabled = biometric.vault.load()?.isAccount(email: session.current?.user.email) == true
        let capability = await biometric.authenticator.capability()
        methodName = capability.methodName
        canEnable = capability.isAvailable
    }

    public func clearError() { errorMessage = nil }

    /// 用重新輸入的帳密綁定:先向後端驗證,而且必須是目前登入的帳號。成功回傳 `true`。
    public func enable(email: String, password: String) async -> Bool {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let verified = try await auth.login(email: trimmed, password: password)
            guard !Task.isCancelled else { return false }
            guard verified.user.id == session.current?.user.id else {
                errorMessage = "請輸入目前登入的帳號"
                return false
            }
            guard biometric.vault.save(SavedCredentials(email: trimmed, password: password)) else {
                errorMessage = "無法儲存，請確認這支手機已設定裝置密碼"
                return false
            }
            isEnabled = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// 關閉:清掉已存帳密。
    public func disable() {
        biometric.vault.delete()
        isEnabled = false
    }
}
