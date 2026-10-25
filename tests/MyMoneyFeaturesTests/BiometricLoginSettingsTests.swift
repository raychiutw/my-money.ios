import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 「我的」的 Face ID 登入開關(#310):開啟要重新輸入帳密、驗證成功且是目前帳號才綁定;關閉就清掉。
@MainActor
@Suite("Face ID 登入設定")
struct BiometricLoginSettingsTests {
    private let auth = InMemoryAuthRepository(members: [.sample])
    private let saved = SavedCredentials(email: "family@example.com", password: "secret123")

    private func make(
        vault: InMemoryCredentialVault = InMemoryCredentialVault(), capability: DeviceAuthCapability = .faceID
    ) async -> (settings: BiometricLoginSettings, vault: InMemoryCredentialVault) {
        let session = AppSession(storage: InMemorySessionStorage())
        session.start(try! await auth.login(email: "family@example.com", password: "secret123"))
        let settings = BiometricLoginSettings(
            auth: auth, session: session,
            biometricLogin: BiometricLogin(vault: vault, authenticator: FakeDeviceAuthenticator(capability: capability))
        )
        await settings.refresh()
        return (settings, vault)
    }

    @Test("沒綁定時是關閉;已綁定目前帳號時是開啟")
    func reflectsVault() async {
        #expect(await !make().settings.isEnabled)
        #expect(await make(vault: InMemoryCredentialVault(saved: saved)).settings.isEnabled)
    }

    @Test("綁定別的帳號不算開啟")
    func otherAccountIsNotEnabled() async {
        let other = SavedCredentials(email: "other@example.com", password: "x")
        #expect(await !make(vault: InMemoryCredentialVault(saved: other)).settings.isEnabled)
    }

    @Test("開啟:帳密正確且是目前帳號,就存下來")
    func enableWithCorrectCredentials() async {
        let (settings, vault) = await make()
        let ok = await settings.enable(email: "family@example.com", password: "secret123")

        #expect(ok)
        #expect(vault.load() == saved)
        #expect(settings.isEnabled)
        #expect(settings.errorMessage == nil)
    }

    @Test("開啟:密碼錯就不存,顯示後端訊息")
    func enableWithWrongPassword() async {
        let (settings, vault) = await make()
        let ok = await settings.enable(email: "family@example.com", password: "wrong")

        #expect(!ok)
        #expect(vault.load() == nil)
        #expect(!settings.isEnabled)
        #expect(settings.errorMessage == "Email 或密碼錯誤")
    }

    @Test("開啟:輸入的是另一個帳號就不綁定")
    func enableWithAnotherAccount() async {
        let other = InMemoryAuthRepository.Member(
            email: "other@example.com", password: "pw", user: User(id: UserID("other"), email: "other@example.com", name: "別人")
        )
        let auth = InMemoryAuthRepository(members: [.sample, other])
        let session = AppSession(storage: InMemorySessionStorage())
        session.start(try! await auth.login(email: "family@example.com", password: "secret123"))
        let vault = InMemoryCredentialVault()
        let settings = BiometricLoginSettings(
            auth: auth, session: session, biometricLogin: BiometricLogin(vault: vault, authenticator: FakeDeviceAuthenticator())
        )
        let ok = await settings.enable(email: "other@example.com", password: "pw")

        #expect(!ok)
        #expect(vault.load() == nil)
        #expect(settings.errorMessage == "請輸入目前登入的帳號")
    }

    @Test("關閉:清掉已存帳密")
    func disableClearsVault() async {
        let (settings, vault) = await make(vault: InMemoryCredentialVault(saved: saved))
        settings.disable()

        #expect(vault.load() == nil)
        #expect(!settings.isEnabled)
    }

    @Test("裝置不能驗證:不能開啟")
    func unavailableCannotEnable() async {
        let (settings, _) = await make(capability: .unavailable)
        #expect(!settings.canEnable)
    }
}
