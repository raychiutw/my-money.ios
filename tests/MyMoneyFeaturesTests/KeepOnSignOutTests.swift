import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("Face ID 登入者登出時保留(#364)")
struct KeepOnSignOutTests {
    private let sample = InMemoryAuthRepository.Member.sample.session

    private func boundStorage(_ result: InMemorySessionStorage.BiometricResult = .pass) -> InMemorySessionStorage {
        InMemorySessionStorage(session: sample, protection: .biometric, biometricResult: result)
    }

    /// 冷啟動刷臉進入後登出。
    private func signedOutKeeping(
        _ storage: InMemorySessionStorage, auth: InMemoryAuthRepository? = nil
    ) async -> AppSession {
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))
        await SignOutModel(auth: auth ?? InMemoryAuthRepository(members: [.sample]), session: session).signOut()
        return session
    }

    @Test("Face ID 登入者登出:不撤銷,保留受保護的 session,顯示登入入口頁")
    func protectedSignOutKeepsSession() async {
        let storage = boundStorage()
        let auth = InMemoryAuthRepository(members: [.sample])

        let session = await signedOutKeeping(storage, auth: auth)

        #expect(session.current == nil)
        #expect(session.showsSignInEntry)
        #expect(await auth.revokedRefreshTokens.isEmpty)
        #expect(storage.stored?.session == sample)
        #expect(storage.stored?.protection == .biometric)
    }

    @Test("一般保存的人登出:撤銷並清掉,不顯示登入入口頁")
    func standardSignOutRevokesAndClears() async {
        let storage = InMemorySessionStorage(session: sample)
        let auth = InMemoryAuthRepository(members: [.sample])
        let session = AppSession(storage: storage)

        await SignOutModel(auth: auth, session: session).signOut()

        #expect(await auth.revokedRefreshTokens == [sample.tokens.refresh])
        #expect(storage.stored == nil)
        #expect(!session.showsSignInEntry)
        #expect(!AppSession(storage: storage).showsSignInEntry)
    }

    @Test("登出後冷啟動:停在登入入口頁,不自動刷臉")
    func coldStartAfterSignOutStaysOnEntry() async {
        let storage = boundStorage()
        _ = await signedOutKeeping(storage)

        let relaunched = AppSession(storage: storage)

        #expect(relaunched.showsSignInEntry)
        #expect(!relaunched.isUnlocking)
        #expect(relaunched.current == nil)
        #expect(storage.biometricPromptCount == 1)
    }

    @Test("入口頁按「登入」:有保留的 session 就刷臉,通過進入 tab 外殼;之後冷啟動照舊自動刷臉")
    func entrySignInUnlocksKeptSession() async {
        let storage = boundStorage()
        let session = await signedOutKeeping(storage)

        session.signInFromEntry()
        #expect(!session.showsSignInEntry)
        #expect(session.isUnlocking)
        await session.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))

        #expect(session.current == sample)
        #expect(session.verifiedByBiometrics)
        #expect(storage.biometricPromptCount == 2)
        #expect(AppSession(storage: storage).isUnlocking)
    }

    @Test("入口頁刷臉取消或失敗:開登入網頁,保留的 session 先不刪,冷啟動仍停在入口頁", arguments: [
        InMemorySessionStorage.BiometricResult.cancel, .fail,
    ])
    func entryCancelOpensWebAndKeeps(result: InMemorySessionStorage.BiometricResult) async {
        let storage = boundStorage()
        let session = await signedOutKeeping(storage)
        storage.setBiometricResult(result)
        let auth = InMemoryAuthRepository(members: [.sample], signInError: CancellationError())
        let login = LoginModel(auth: auth, session: session)

        session.signInFromEntry()
        await session.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))

        #expect(session.current == nil)
        #expect(!session.showsSignInEntry)
        #expect(!session.isUnlocking)
        #expect(storage.stored?.session == sample)
        #expect(storage.stored?.protection == .biometric)
        // 未登入畫面接著開登入網頁(這裡關掉視窗後 scene 離開前景,不再重開)。
        let opening = Task { await login.appeared() }
        while await auth.signInRequests.isEmpty { await Task.yield() }
        login.sceneLeftForeground()
        await opening.value
        #expect(storage.stored?.protection == .biometric)
        #expect(AppSession(storage: storage).showsSignInEntry)
    }

    @Test("入口頁按「登入」但沒有保留的 session(已失效被清掉):直接開登入網頁")
    func entryWithoutKeptSessionOpensWeb() async {
        let storage = boundStorage()
        let session = await signedOutKeeping(storage)
        storage.clear()
        let auth = InMemoryAuthRepository(members: [.sample])

        session.signInFromEntry()
        #expect(!session.isUnlocking)
        await LoginModel(auth: auth, session: session).appeared()

        #expect(await auth.signInRequests == [false])
        #expect(session.current == sample)
    }

    @Test("刷臉取消後網頁登入同一個帳號:保存換成新的 session,仍受保護、Face ID 登入維持開啟,不再停在入口頁")
    func webSignInSameAccountReplaces() async {
        let storage = boundStorage(.cancel)
        let session = await signedOutKeepingAfterCancel(storage)
        let renewed = Session(user: sample.user, tokens: SessionTokens(access: "a2", refresh: "r2", accessExpiresAt: nil))
        let prompts = storage.biometricPromptCount

        session.start(renewed)

        #expect(storage.stored?.session == renewed)
        #expect(storage.stored?.protection == .biometric)
        #expect(session.isBiometricSignInEnabled)
        #expect(storage.biometricPromptCount == prompts)
        let relaunched = AppSession(storage: storage)
        #expect(!relaunched.showsSignInEntry)
        #expect(relaunched.isUnlocking)
    }

    @Test("登出後冷啟動、刷臉取消,網頁登入同一個帳號:一樣仍受保護")
    func webSignInSameAccountAfterColdStartStaysProtected() async {
        let storage = boundStorage()
        _ = await signedOutKeeping(storage)
        storage.setBiometricResult(.cancel)
        let relaunched = AppSession(storage: storage)
        relaunched.signInFromEntry()
        await relaunched.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))
        let renewed = Session(user: sample.user, tokens: SessionTokens(access: "a2", refresh: "r2", accessExpiresAt: nil))

        relaunched.start(renewed)

        #expect(storage.stored?.session == renewed)
        #expect(storage.stored?.protection == .biometric)
        #expect(relaunched.isBiometricSignInEnabled)
    }

    @Test("刷臉取消後網頁按「用 Face ID 登入」重新綁定:之後冷啟動照舊自動刷臉,不停在入口頁")
    func webBiometricSignInRebindsAndForgetsSignOut() async {
        let storage = boundStorage(.cancel)
        let session = await signedOutKeepingAfterCancel(storage)
        storage.setBiometricResult(.pass)

        await session.start(SignInResult(session: sample, biometric: true))

        #expect(storage.stored?.protection == .biometric)
        let relaunched = AppSession(storage: storage)
        #expect(relaunched.isUnlocking)
        #expect(!relaunched.showsSignInEntry)
    }

    @Test("刷臉取消後網頁登入另一個帳號:前一個人的保存清掉,換成新的人")
    func webSignInOtherAccountClearsPrevious() async {
        let storage = boundStorage(.cancel)
        let session = await signedOutKeepingAfterCancel(storage)
        let other = InMemoryAuthRepository.Member(user: User(id: UserID("other"), email: "other@example.com", name: "小美"))
        let auth = InMemoryAuthRepository(members: [other])

        await LoginModel(auth: auth, session: session).appeared()

        #expect(session.current == other.session)
        #expect(storage.stored?.session == other.session)
        #expect(storage.stored?.protection == .standard)
        let relaunched = AppSession(storage: storage)
        #expect(!relaunched.showsSignInEntry)
        #expect(relaunched.current == other.session)
    }

    @Test("入口頁刷臉進入後 refresh 被拒:清掉保存,開登入網頁")
    func refreshRejectedAfterEntryClears() async {
        let storage = boundStorage()
        let session = await signedOutKeeping(storage)
        session.signInFromEntry()
        await session.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))

        _ = await session.sessionDidExpire(refresh: sample.tokens.refresh)

        #expect(storage.stored == nil)
        #expect(!session.showsSignInEntry)
        let relaunched = AppSession(storage: storage)
        #expect(!relaunched.showsSignInEntry)
        #expect(!relaunched.isUnlocking)
    }

    @Test("入口頁刷臉時保存已失效(臉部資料變更):清掉,開登入網頁")
    func entryInvalidatedClears() async {
        let storage = boundStorage()
        let session = await signedOutKeeping(storage)
        storage.setBiometricResult(.invalidate)

        session.signInFromEntry()
        await session.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))

        #expect(session.current == nil)
        #expect(!session.showsSignInEntry)
        #expect(storage.stored == nil)
        #expect(!AppSession(storage: storage).showsSignInEntry)
    }

    @Test("登出前送出的 refresh 晚回來:保留的 session 換成輪替後的權杖,仍受保護、不登入")
    func lateRefreshUpdatesKeptSession() async {
        let storage = boundStorage()
        let session = await signedOutKeeping(storage)
        let rotated = SessionTokens(access: "new-access", refresh: "rotated-refresh", accessExpiresAt: nil)

        await session.sessionDidRefresh(rotated, replacing: sample.tokens.refresh)

        #expect(session.current == nil)
        #expect(storage.stored?.session.tokens == rotated)
        #expect(storage.stored?.protection == .biometric)
        #expect(storage.biometricPromptCount == 1)
    }

    @Test("登出前送出的請求晚回 401:不清掉保留的 session,仍停在入口頁")
    func lateExpiryKeepsKeptSession() async {
        let storage = boundStorage()
        let session = await signedOutKeeping(storage)

        _ = await session.sessionDidExpire(refresh: sample.tokens.refresh)

        #expect(storage.stored?.session == sample)
        #expect(storage.stored?.protection == .biometric)
        #expect(session.showsSignInEntry)
        #expect(AppSession(storage: storage).showsSignInEntry)
    }

    @Test("刪除帳號照舊全部清掉,不顯示登入入口頁")
    func accountDeletionClearsEverything() async {
        let storage = boundStorage()
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))

        session.signOutAfterAccountDeletion()

        #expect(storage.stored == nil)
        #expect(!session.showsSignInEntry)
    }

    /// 登出後在入口頁按「登入」、刷臉取消(接著會開登入網頁)。
    private func signedOutKeepingAfterCancel(_ storage: InMemorySessionStorage) async -> AppSession {
        storage.setBiometricResult(.pass)
        let session = await signedOutKeeping(storage)
        storage.setBiometricResult(.cancel)
        session.signInFromEntry()
        await session.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))
        return session
    }
}
