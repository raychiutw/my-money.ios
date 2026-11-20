import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 任何主動登出後都顯示登入入口頁(#367,對齊 trip-planner ADR-0020):不論有沒有開 Face ID 登入,冷啟動也停在這頁。
/// session 過期、被撤銷、刪除帳號與從沒登入過,照舊自動開登入網頁。
@MainActor
@Suite("主動登出後顯示登入入口頁(#367)")
struct SignInEntryAfterSignOutTests {
    private let sample = InMemoryAuthRepository.Member.sample.session

    /// 一般保存的人登入後主動登出。
    private func signedOut(
        _ storage: InMemorySessionStorage, auth: InMemoryAuthRepository? = nil
    ) async -> AppSession {
        let session = AppSession(storage: storage)
        await SignOutModel(auth: auth ?? InMemoryAuthRepository(members: [.sample]), session: session).signOut()
        return session
    }

    @Test("一般保存的人主動登出:撤銷並清掉,顯示登入入口頁;冷啟動也停在入口頁")
    func standardSignOutShowsEntry() async {
        let storage = InMemorySessionStorage(session: sample)
        let auth = InMemoryAuthRepository(members: [.sample])

        let session = await signedOut(storage, auth: auth)

        #expect(await auth.revokedRefreshTokens == [sample.tokens.refresh])
        #expect(storage.stored == nil)
        #expect(session.current == nil)
        #expect(session.showsSignInEntry)
        let relaunched = AppSession(storage: storage)
        #expect(relaunched.showsSignInEntry)
        #expect(!relaunched.isUnlocking)
        #expect(relaunched.current == nil)
    }

    @Test("入口頁按「登入」沒有保留的 session:直接開登入網頁,登入成功後冷啟動直接進首頁")
    func entrySignInOpensWebAndForgetsSignOut() async {
        let storage = InMemorySessionStorage(session: sample)
        let session = await signedOut(storage)
        let auth = InMemoryAuthRepository(members: [.sample])

        session.signInFromEntry()
        #expect(!session.showsSignInEntry)
        #expect(!session.isUnlocking)
        await LoginModel(auth: auth, session: session).appeared()

        #expect(await auth.signInRequests == [false])
        #expect(session.current == sample)
        let relaunched = AppSession(storage: storage)
        #expect(!relaunched.showsSignInEntry)
        #expect(relaunched.current == sample)
    }

    // 關掉後一直重開的話不會結束:限時一分鐘。
    @Test("入口頁開的登入網頁被關掉:回到入口頁,不再重開", .timeLimit(.minutes(1)))
    func closingWebFromEntryReturnsToEntry() async {
        let storage = InMemorySessionStorage(session: sample)
        let session = await signedOut(storage)
        let auth = InMemoryAuthRepository(members: [.sample], signInError: CancellationError())
        let login = LoginModel(auth: auth, session: session)

        session.signInFromEntry()
        await login.appeared()

        #expect(await auth.signInRequests == [false])
        #expect(session.current == nil)
        #expect(session.showsSignInEntry)
        #expect(login.errorMessage == nil)
        #expect(AppSession(storage: storage).showsSignInEntry)
    }

    // 關掉後一直重開的話不會結束:限時一分鐘。
    @Test("Face ID 登入的人在入口頁刷臉取消、接著開的登入網頁也關掉:回到入口頁,保留的 session 還在", .timeLimit(.minutes(1)))
    func closingWebAfterFaceCancelReturnsToEntry() async {
        let storage = InMemorySessionStorage(session: sample, protection: .biometric)
        let session = AppSession(storage: storage)
        await session.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))
        await SignOutModel(auth: InMemoryAuthRepository(members: [.sample]), session: session).signOut()
        storage.setBiometricResult(.cancel)
        let auth = InMemoryAuthRepository(members: [.sample], signInError: CancellationError())

        session.signInFromEntry()
        await session.unlockProtectedSession(refreshingWith: InMemoryAuthRepository(members: [.sample]))
        await LoginModel(auth: auth, session: session).appeared()

        #expect(await auth.signInRequests == [false])
        #expect(session.showsSignInEntry)
        #expect(storage.stored?.protection == .biometric)
    }

    @Test("過期與刪除帳號不是主動登出:不顯示入口頁,冷啟動自動開登入網頁")
    func expiryAndDeletionDoNotShowEntry() async {
        let expiredStorage = InMemorySessionStorage(session: sample)
        let expired = AppSession(storage: expiredStorage)
        _ = await expired.sessionDidExpire(refresh: sample.tokens.refresh)
        #expect(!expired.showsSignInEntry)
        #expect(!AppSession(storage: expiredStorage).showsSignInEntry)

        let deletedStorage = InMemorySessionStorage(session: sample)
        let deleted = AppSession(storage: deletedStorage)
        deleted.signOutAfterAccountDeletion()
        #expect(!deleted.showsSignInEntry)
        #expect(!AppSession(storage: deletedStorage).showsSignInEntry)

        #expect(!AppSession(storage: InMemorySessionStorage()).showsSignInEntry)
    }

    @Test("主動登出後在入口頁開的登入網頁,登入回 session 過期:之後不再停在入口頁")
    func expiryAfterSignInFromEntryForgetsSignOut() async {
        let storage = InMemorySessionStorage(session: sample)
        let session = await signedOut(storage)
        session.signInFromEntry()
        await LoginModel(auth: InMemoryAuthRepository(members: [.sample]), session: session).appeared()

        _ = await session.sessionDidExpire(refresh: sample.tokens.refresh)

        #expect(!session.showsSignInEntry)
        #expect(!AppSession(storage: storage).showsSignInEntry)
    }
}
