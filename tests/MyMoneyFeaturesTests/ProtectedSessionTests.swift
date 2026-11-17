import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("Face ID 登入:受生物辨識保護的 session(#357)")
struct ProtectedSessionTests {
    private let sample = InMemoryAuthRepository.Member.sample.session
    private let rotated = SessionTokens(access: "new-access", refresh: "rotated-refresh", accessExpiresAt: nil)

    private func boundStorage(_ result: InMemorySessionStorage.BiometricResult = .pass) -> InMemorySessionStorage {
        InMemorySessionStorage(session: sample, protection: .biometric, biometricResult: result)
    }

    @Test("生物辨識登入:刷臉通過,綁定成受保護的 session 並進入 tab 外殼")
    func biometricSignInBindsOnPass() async {
        let storage = InMemorySessionStorage()
        let session = AppSession(storage: storage)

        await session.start(SignInResult(session: sample, biometric: true))

        #expect(session.current == sample)
        #expect(storage.stored?.protection == .biometric)
        #expect(storage.biometricPromptCount == 1)
    }

    @Test("生物辨識登入:刷臉取消,仍然登入,改用一般保存")
    func biometricSignInFallsBackToStandardOnCancel() async {
        let storage = InMemorySessionStorage(biometricResult: .cancel)
        let session = AppSession(storage: storage)

        await session.start(SignInResult(session: sample, biometric: true))

        #expect(session.current == sample)
        #expect(storage.stored?.protection == .standard)
        #expect(storage.biometricPromptCount == 1)
    }

    @Test("登入網頁按「用 Face ID 登入」:登入並綁定")
    func loginModelBindsBiometricSignIn() async {
        let storage = InMemorySessionStorage()
        let session = AppSession(storage: storage)
        let auth = InMemoryAuthRepository(members: [.sample], signsInBiometric: true)

        await LoginModel(auth: auth, session: session).appeared()

        #expect(session.current?.user.name == "小明")
        #expect(storage.stored?.protection == .biometric)
    }

    @Test("一般登入不刷臉,用一般保存")
    func plainSignInDoesNotPrompt() async {
        let storage = InMemorySessionStorage()
        let session = AppSession(storage: storage)

        await session.start(SignInResult(session: sample, biometric: false))

        #expect(session.current == sample)
        #expect(storage.stored?.protection == .standard)
        #expect(storage.biometricPromptCount == 0)
    }

    @Test("冷啟動有受保護的 session:先刷臉,通過才進入 tab 外殼")
    func coldStartUnlocksOnPass() async {
        let storage = boundStorage()
        let session = AppSession(storage: storage)

        #expect(session.isUnlocking)
        #expect(session.current == nil)
        await session.unlockProtectedSession()

        #expect(!session.isUnlocking)
        #expect(session.current == sample)
        #expect(session.didRestoreFromStorage)
        #expect(storage.biometricPromptCount == 1)
    }

    @Test("冷啟動刷臉取消或失敗:未登入,綁定留著下次再試", arguments: [
        InMemorySessionStorage.BiometricResult.cancel, .fail,
    ])
    func coldStartStaysSignedOutOnCancelOrFail(result: InMemorySessionStorage.BiometricResult) async {
        let storage = boundStorage(result)
        let session = AppSession(storage: storage)

        await session.unlockProtectedSession()

        #expect(!session.isUnlocking)
        #expect(session.current == nil)
        #expect(storage.stored?.protection == .biometric)
    }

    @Test("冷啟動刷臉取消後網頁一般登入同一個帳號:保存換成新的 session,仍受保護(不刷臉),Face ID 登入維持開啟")
    func plainSignInAfterCancelKeepsBindingForSameUser() async {
        let storage = boundStorage(.cancel)
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession()
        let renewed = Session(user: sample.user, tokens: rotated)

        await session.start(SignInResult(session: renewed, biometric: false))

        #expect(storage.stored?.session == renewed)
        #expect(storage.stored?.protection == .biometric)
        #expect(session.isBiometricSignInEnabled)
        #expect(storage.biometricPromptCount == 1)
    }

    @Test("冷啟動刷臉取消後網頁一般登入另一個帳號:前一個人的保存清掉,新的人用一般保存")
    func plainSignInAfterCancelReplacesBindingForOtherUser() async {
        let storage = boundStorage(.cancel)
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession()
        let other = Session(user: User(id: UserID("other"), email: "other@example.com", name: "小美"), tokens: rotated)

        await session.start(SignInResult(session: other, biometric: false))

        #expect(storage.stored?.session == other)
        #expect(storage.stored?.protection == .standard)
        #expect(!session.isBiometricSignInEnabled)
    }

    @Test("冷啟動保存已失效(臉部資料變更):清掉,未登入")
    func coldStartClearsInvalidatedSession() async {
        let storage = boundStorage(.invalidate)
        let session = AppSession(storage: storage)

        await session.unlockProtectedSession()

        #expect(session.current == nil)
        #expect(storage.stored == nil)
    }

    @Test("冷啟動是一般保存的 session:不刷臉,直接進入")
    func coldStartWithStandardSessionDoesNotPrompt() {
        let storage = InMemorySessionStorage(session: sample)
        let session = AppSession(storage: storage)

        #expect(!session.isUnlocking)
        #expect(session.current == sample)
        #expect(storage.biometricPromptCount == 0)
    }

    @Test("refresh 輪替:受保護的保存換成新的權杖,不刷臉")
    func refreshKeepsProtectionWithoutPrompt() async {
        let storage = boundStorage()
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession()

        await session.sessionDidRefresh(rotated, replacing: sample.tokens.refresh)

        #expect(storage.stored?.session.tokens == rotated)
        #expect(storage.stored?.protection == .biometric)
        #expect(storage.biometricPromptCount == 1)
    }

    @Test("登出清掉受保護的 session")
    func signOutClearsProtectedSession() async {
        let storage = boundStorage()
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession()

        session.signOut()

        #expect(storage.stored == nil)
    }

    @Test("刪除帳號清掉受保護的 session")
    func accountDeletionClearsProtectedSession() async {
        let storage = boundStorage()
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession()

        session.signOutAfterAccountDeletion()

        #expect(storage.stored == nil)
    }

    @Test("session 過期清掉受保護的 session")
    func expiryClearsProtectedSession() async {
        let storage = boundStorage()
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession()

        _ = await session.sessionDidExpire(refresh: sample.tokens.refresh)

        #expect(storage.stored == nil)
    }

    // MARK: 與 App 鎖不重複刷臉(#358)

    @Test("冷啟動刷臉讀出 session:標記這次已用生物辨識驗證(App 鎖不再鎖)")
    func coldStartUnlockIsVerifiedByBiometrics() async {
        let session = AppSession(storage: boundStorage())
        await session.unlockProtectedSession()
        #expect(session.verifiedByBiometrics)
    }

    @Test("冷啟動讀回一般保存的 session:沒有用生物辨識驗證")
    func standardRestoreIsNotVerifiedByBiometrics() {
        let session = AppSession(storage: InMemorySessionStorage(session: sample))
        #expect(!session.verifiedByBiometrics)
    }

    @Test("剛完成 Face ID 綁定:已用生物辨識驗證;綁定取消則否")
    func bindingIsVerifiedByBiometrics() async {
        let bound = AppSession(storage: InMemorySessionStorage())
        await bound.start(SignInResult(session: sample, biometric: true))
        #expect(bound.verifiedByBiometrics)

        let cancelled = AppSession(storage: InMemorySessionStorage(biometricResult: .cancel))
        await cancelled.start(SignInResult(session: sample, biometric: true))
        #expect(!cancelled.verifiedByBiometrics)
    }

    // MARK: 「我的」的「使用 Face ID 登入」開關(#358)

    @Test("開關反映目前的保存:Face ID 登入的冷啟動是開,一般保存是關")
    func switchReflectsStoredProtection() async {
        let bound = AppSession(storage: boundStorage())
        await bound.unlockProtectedSession()
        #expect(bound.isBiometricSignInEnabled)

        let standard = AppSession(storage: InMemorySessionStorage(session: sample))
        #expect(!standard.isBiometricSignInEnabled)
    }

    @Test("開啟:刷臉通過才開,改成受保護的保存,仍然登入")
    func enablingBindsOnPass() async {
        let storage = InMemorySessionStorage(session: sample)
        let session = AppSession(storage: storage)

        await session.setBiometricSignIn(true)

        #expect(session.isBiometricSignInEnabled)
        #expect(storage.stored?.protection == .biometric)
        #expect(storage.stored?.session == sample)
        #expect(storage.biometricPromptCount == 1)
        #expect(session.current == sample)
    }

    @Test("開啟時刷臉取消或失敗:維持關閉,一般保存,仍然登入", arguments: [
        InMemorySessionStorage.BiometricResult.cancel, .fail, .invalidate,
    ])
    func enablingStaysOffOnCancel(result: InMemorySessionStorage.BiometricResult) async {
        let storage = InMemorySessionStorage(session: sample, biometricResult: result)
        let session = AppSession(storage: storage)

        await session.setBiometricSignIn(true)

        #expect(!session.isBiometricSignInEnabled)
        #expect(storage.stored?.protection == .standard)
        #expect(storage.stored?.session == sample)
        #expect(session.current == sample)
    }

    @Test("關閉:改回一般保存,不刷臉,不登出")
    func disablingKeepsSignedIn() async {
        let storage = boundStorage()
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession()

        await session.setBiometricSignIn(false)

        #expect(!session.isBiometricSignInEnabled)
        #expect(storage.stored?.protection == .standard)
        #expect(storage.stored?.session == sample)
        #expect(storage.biometricPromptCount == 1)
        #expect(session.current == sample)
    }

    @Test("登出後開關回到關")
    func signOutTurnsSwitchOff() async {
        let session = AppSession(storage: boundStorage())
        await session.unlockProtectedSession()
        session.signOut()
        #expect(!session.isBiometricSignInEnabled)
    }

    // MARK: 刷臉期間 session 變了(code review)

    @Test("開啟 Face ID 登入刷臉期間過期或登出:不把舊 session 寫回保存", arguments: [
        InMemorySessionStorage.BiometricResult.pass, .cancel,
    ])
    func bindingDoesNotRestoreEndedSession(result: InMemorySessionStorage.BiometricResult) async {
        let gate = Gate()
        let storage = InMemorySessionStorage(session: sample, biometricResult: result, gate: gate)
        let session = AppSession(storage: storage)

        let enabling = Task { await session.setBiometricSignIn(true) }
        await gate.waitUntilReached()
        _ = await session.sessionDidExpire(refresh: sample.tokens.refresh)
        await gate.open()
        await enabling.value

        #expect(storage.stored == nil)
        #expect(session.current == nil)
        #expect(!session.isBiometricSignInEnabled)
    }

    @Test("開啟 Face ID 登入刷臉期間登出又換人登入:保存是新的 session")
    func bindingDoesNotOverwriteNewSession() async {
        let gate = Gate()
        let storage = InMemorySessionStorage(session: sample, biometricResult: .cancel, gate: gate)
        let session = AppSession(storage: storage)
        let other = Session(user: sample.user, tokens: rotated)

        let enabling = Task { await session.setBiometricSignIn(true) }
        await gate.waitUntilReached()
        session.signOut()
        session.start(other)
        await gate.open()
        await enabling.value

        #expect(storage.stored?.session == other)
        #expect(storage.stored?.protection == .standard)
        #expect(session.current == other)
    }

    @Test("登入時綁定刷臉期間登出:不登入、不留下保存")
    func signInBindingAbandonedAfterSignOut() async {
        let gate = Gate()
        let storage = InMemorySessionStorage(gate: gate)
        let session = AppSession(storage: storage)

        let signingIn = Task { await session.start(SignInResult(session: sample, biometric: true)) }
        await gate.waitUntilReached()
        session.signOut()
        await gate.open()
        await signingIn.value

        #expect(storage.stored == nil)
        #expect(session.current == nil)
    }

    @Test("綁定的刷臉提示依裝置寫生物辨識名稱", arguments: [
        (DeviceAuthCapability.faceID, "Face ID"), (.touchID, "Touch ID"), (.opticID, "Optic ID"),
    ])
    func bindingPromptNamesBiometry(capability: DeviceAuthCapability, name: String) async {
        let storage = InMemorySessionStorage()
        let session = AppSession(storage: storage, authenticator: FakeDeviceAuthenticator(capability: capability))

        await session.start(SignInResult(session: sample, biometric: true))

        #expect(storage.lastPromptReason == "以後打開「我的記帳本」直接用 \(name) 登入")
    }
}
