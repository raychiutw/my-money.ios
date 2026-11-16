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

        await LoginModel(auth: auth, session: session).signIn()

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

    @Test("冷啟動刷臉取消後改用一般登入:新的 session 用一般保存,取代舊的綁定")
    func plainSignInAfterCancelReplacesBinding() async {
        let storage = boundStorage(.cancel)
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession()
        let other = Session(user: sample.user, tokens: rotated)

        await session.start(SignInResult(session: other, biometric: false))

        #expect(storage.stored?.session == other)
        #expect(storage.stored?.protection == .standard)
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

        await session.sessionDidExpire()

        #expect(storage.stored == nil)
    }
}
