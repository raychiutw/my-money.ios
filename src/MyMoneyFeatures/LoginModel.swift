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

    /// 登入頁有沒有「使用 Face ID 登入」的按鈕:有存帳密、而且這支裝置現在還能驗證本人。
    public private(set) var canUseBiometricLogin = false

    /// 登入成功、還沒進入 app:正在問「要不要用 Face ID 登入」(回答後才進入)。
    public private(set) var isOfferingBiometricLogin = false

    /// 按鈕與詢問裡的驗證方式名稱(Face ID、Touch ID、Optic ID、裝置密碼)。
    public private(set) var biometricMethodName = "Face ID"

    public var biometricLoginTitle: String { "使用 \(biometricMethodName) 登入" }

    @ObservationIgnored private let auth: any AuthRepository
    @ObservationIgnored private let session: AppSession
    @ObservationIgnored private let biometric: BiometricLogin?
    /// 詢問期間暫存:登入成功的 session 與剛輸入的帳密。
    @ObservationIgnored private var pendingOffer: (session: Session, credentials: SavedCredentials)?

    public init(auth: any AuthRepository, session: AppSession, biometricLogin: BiometricLogin? = nil) {
        self.auth = auth
        self.session = session
        biometric = biometricLogin
    }

    /// 重新判斷要不要顯示 Face ID 登入按鈕(登入頁出現時呼叫)。
    public func refreshBiometricLogin() async {
        guard let biometric, biometric.vault.hasSaved() else {
            canUseBiometricLogin = false
            return
        }
        let capability = await biometric.authenticator.capability()
        biometricMethodName = capability.methodName
        canUseBiometricLogin = capability.isAvailable
    }

    /// 按「使用 Face ID 登入」:驗證通過就用已存的帳密登入。
    public func signInWithBiometrics() async {
        guard let biometric, let credentials = biometric.vault.load() else { return }
        errorMessage = nil
        switch await biometric.authenticator.authenticate(reason: "登入我的記帳本") {
        case .success:
            break
        case .cancelled:
            return
        case .failed, .unavailable:
            errorMessage = "\(biometricMethodName) 驗證失敗，請改用密碼登入"
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            session.start(try await auth.login(email: credentials.email, password: credentials.password))
        } catch RepositoryError.rejected(let message) {
            // 密碼已經在別處改掉:已存的帳密沒用了,清掉,請使用者用新密碼登入。
            biometric.vault.delete()
            canUseBiometricLogin = false
            errorMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 刪除帳號後:已存的帳密一併清掉。
    public func forgetSavedLogin() {
        biometric?.vault.delete()
        canUseBiometricLogin = false
    }

    /// 回答「要不要用 Face ID 登入」:要就存帳密,然後進入 app。
    public func answerBiometricOffer(save: Bool) {
        guard let pending = pendingOffer, let biometric else { return }
        pendingOffer = nil
        isOfferingBiometricLogin = false
        if save {
            biometric.vault.save(pending.credentials)
            canUseBiometricLogin = true
        } else {
            biometric.defaults.set(true, forKey: Self.declinedKey(pending.credentials.email))
        }
        session.start(pending.session)
    }

    private static func declinedKey(_ email: String) -> String { "biometricLogin.declined.\(email)" }

    /// 送出登入。
    public func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let signedIn = try await auth.login(email: trimmedEmail, password: password)
            let credentials = SavedCredentials(email: trimmedEmail, password: password)
            // 清空表單：登出回來時跟 web 一樣是空白的登入頁，密碼也不留在記憶體裡。
            email = ""
            password = ""
            isPasswordVisible = false
            if let biometric {
                if biometric.vault.load()?.email == credentials.email {
                    // 已經存過這個帳號:密碼有改就靜默更新,不再詢問。
                    biometric.vault.save(credentials)
                } else if !biometric.vault.hasSaved(),
                    !biometric.defaults.bool(forKey: Self.declinedKey(credentials.email)),
                    await biometric.authenticator.capability().isAvailable
                {
                    biometricMethodName = await biometric.authenticator.capability().methodName
                    pendingOffer = (signedIn, credentials)
                    isOfferingBiometricLogin = true
                    return
                }
            }
            session.start(signedIn)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Face ID 登入需要的三個協作者(#308):帳密保管箱、驗證本人、記錄「已經問過不要」的設定。
public struct BiometricLogin {
    let vault: any CredentialVault
    let authenticator: any DeviceAuthenticator
    let defaults: UserDefaults

    public init(vault: any CredentialVault, authenticator: any DeviceAuthenticator, defaults: UserDefaults) {
        self.vault = vault
        self.authenticator = authenticator
        self.defaults = defaults
    }
}

extension DeviceAuthCapability {
    var methodName: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .passcodeOnly, .unavailable: "裝置密碼"
        }
    }
}
