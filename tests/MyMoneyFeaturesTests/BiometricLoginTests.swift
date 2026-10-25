import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 用 Face ID 登入(#308):登入成功後問一次要不要記住,之後登入頁用 Face ID 帶入已存的帳密。
@MainActor
@Suite("Face ID 登入")
struct BiometricLoginTests {
    private let auth: any AuthRepository = InMemoryAuthRepository(members: [.sample])
    private let saved = SavedCredentials(email: "family@example.com", password: "secret123")

    private func make(
        vault: InMemoryCredentialVault = InMemoryCredentialVault(), auth: (any AuthRepository)? = nil,
        capability: DeviceAuthCapability = .faceID, result: DeviceAuthResult = .success
    ) -> (model: LoginModel, session: AppSession, vault: InMemoryCredentialVault) {
        let session = AppSession(storage: InMemorySessionStorage())
        let model = LoginModel(
            auth: auth ?? self.auth, session: session,
            biometricLogin: BiometricLogin(
                vault: vault, authenticator: FakeDeviceAuthenticator(capability: capability, result: result)
            )
        )
        return (model, session, vault)
    }

    private func fillAndSubmit(_ model: LoginModel, password: String = "secret123", remember: Bool = false) async {
        model.remembersBiometricLogin = remember
        model.email = "family@example.com"
        model.password = password
        await model.submit()
    }

    @Test("有存帳密:登入頁出現 Face ID 按鈕;沒存就沒有")
    func buttonOnlyWhenSaved() async {
        let without = make()
        await without.model.refreshBiometricLogin()
        #expect(!without.model.canUseBiometricLogin)

        let with = make(vault: InMemoryCredentialVault(saved: saved))
        await with.model.refreshBiometricLogin()
        #expect(with.model.canUseBiometricLogin)
        #expect(with.model.biometricLoginTitle == "使用 Face ID 登入")
    }

    @Test("按 Face ID 登入:驗證通過就用已存的帳密登入")
    func biometricSignIn() async {
        let (model, session, _) = make(vault: InMemoryCredentialVault(saved: saved))
        await model.signInWithBiometrics()

        #expect(session.current?.user.name == "小明")
    }

    @Test("驗證取消:留在登入頁、沒有錯誤訊息;驗證失敗:顯示訊息")
    func cancelAndFail() async {
        let cancelled = make(vault: InMemoryCredentialVault(saved: saved), result: .cancelled)
        await cancelled.model.signInWithBiometrics()
        #expect(cancelled.session.current == nil)
        #expect(cancelled.model.errorMessage == nil)

        let failed = make(vault: InMemoryCredentialVault(saved: saved), result: .failed)
        await failed.model.signInWithBiometrics()
        #expect(failed.session.current == nil)
        #expect(failed.model.errorMessage != nil)
    }

    @Test("已存的密碼過期(後端拒絕):清掉已存帳密、顯示後端訊息、按鈕消失")
    func staleCredentialsAreDeleted() async {
        let stale = SavedCredentials(email: "family@example.com", password: "old-password")
        let (model, session, vault) = make(vault: InMemoryCredentialVault(saved: stale))
        await model.refreshBiometricLogin()
        await model.signInWithBiometrics()

        #expect(session.current == nil)
        #expect(vault.load() == nil)
        #expect(model.errorMessage == "Email 或密碼錯誤")
        #expect(!model.canUseBiometricLogin)
    }

    @Test("用密碼登入時已有存帳密:靜默更新成新的密碼")
    func passwordLoginRefreshesSaved() async {
        let (model, session, vault) = make(vault: InMemoryCredentialVault(saved: saved))
        await fillAndSubmit(model)

        #expect(session.current != nil)
        #expect(vault.load() == saved)
    }

    @Test("登入頁勾選「下次使用 Face ID 登入」且登入成功:存帳密並進入")
    func rememberOnLoginSaves() async {
        let (model, session, vault) = make()
        await fillAndSubmit(model, remember: true)

        #expect(vault.load() == saved)
        #expect(session.current != nil)
        #expect(model.canUseBiometricLogin)
        #expect(!model.remembersBiometricLogin)
    }

    @Test("沒勾選:不存")
    func notRememberedByDefault() async {
        let (model, session, vault) = make()
        await fillAndSubmit(model)

        #expect(vault.load() == nil)
        #expect(session.current != nil)
    }

    @Test("勾了但登入失敗(密碼錯):不存")
    func failedLoginDoesNotSave() async {
        let (model, session, vault) = make()
        await fillAndSubmit(model, password: "wrong", remember: true)

        #expect(vault.load() == nil)
        #expect(session.current == nil)
    }

    @Test("裝置不能驗證:不提供勾選,勾了也不存")
    func unavailableDeviceNeverSaves() async {
        let (model, session, vault) = make(capability: .unavailable)
        await model.refreshBiometricLogin()
        #expect(!model.canOfferBiometricLogin)
        await fillAndSubmit(model, remember: true)

        #expect(vault.load() == nil)
        #expect(session.current != nil)
    }

    @Test("可驗證且還沒綁定:登入頁提供勾選;已綁定就改顯示按鈕、不提供勾選")
    func offerOnlyWhenNotBound() async {
        let fresh = make()
        await fresh.model.refreshBiometricLogin()
        #expect(fresh.model.canOfferBiometricLogin)

        let bound = make(vault: InMemoryCredentialVault(saved: saved))
        await bound.model.refreshBiometricLogin()
        #expect(!bound.model.canOfferBiometricLogin)
    }

    @Test("存不進去(例如沒設裝置密碼):不顯示 Face ID 按鈕")
    func failedSaveDoesNotEnableButton() async {
        let (model, _, vault) = make(vault: InMemoryCredentialVault(failsToSave: true))
        await fillAndSubmit(model, remember: true)

        #expect(vault.load() == nil)
        #expect(!model.canUseBiometricLogin)
    }

    @Test("後端暫時出錯(不是密碼錯誤):不清掉已存帳密,按鈕還在")
    func transientFailureKeepsSaved() async {
        let (model, session, vault) = make(vault: InMemoryCredentialVault(saved: saved), auth: FailingAuth(error: RepositoryError.rejected("請求太頻繁")))
        await model.refreshBiometricLogin()
        await model.signInWithBiometrics()

        #expect(session.current == nil)
        #expect(vault.load() == saved)
        #expect(model.canUseBiometricLogin)
        #expect(model.errorMessage == "請求太頻繁")
    }

    @Test("按鈕出現後 Keychain 項目不見了:按下去不登入、按鈕消失")
    func vanishedCredentialsHideButton() async {
        let (model, session, vault) = make(vault: InMemoryCredentialVault(saved: saved))
        await model.refreshBiometricLogin()
        vault.delete()
        await model.signInWithBiometrics()

        #expect(session.current == nil)
        #expect(!model.canUseBiometricLogin)
    }
}

private struct FailingAuth: AuthRepository {
    let error: RepositoryError
    func login(email: String, password: String) async throws -> Session { throw error }
    func register(name: String, email: String, password: String) async throws -> Session { throw error }
    func deleteAccount() async throws { throw error }
}
