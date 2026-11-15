import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("登出(撤銷登入工作階段)")
struct SignOutTests {
    private let storage = InMemorySessionStorage(session: InMemoryAuthRepository.Member.sample.session)

    @Test("登出撤銷伺服器端的登入工作階段(送出這台的更新權杖)")
    func signOutRevokesSession() async {
        let auth = InMemoryAuthRepository(members: [.sample])
        let session = AppSession(storage: storage)

        await SignOutModel(auth: auth, session: session).signOut()

        #expect(await auth.revokedRefreshTokens == ["in-memory-refresh-in-memory-member-1"])
        #expect(session.current == nil)
        #expect(AppSession(storage: storage).current == nil)
    }

    @Test("撤銷還沒完成(或失敗)時,本機已經登出、回到登入頁")
    func localSignOutDoesNotWaitForRevocation() async {
        let gate = Gate()
        let session = AppSession(storage: storage)
        let model = SignOutModel(auth: InMemoryAuthRepository(members: [.sample], gate: gate), session: session)

        let signingOut = Task { await model.signOut() }
        await gate.waitUntilReached()

        #expect(session.current == nil)
        #expect(AppSession(storage: storage).current == nil)

        await gate.open()
        await signingOut.value
    }

    @Test("沒有登入時不撤銷")
    func signedOutDoesNothing() async {
        let auth = InMemoryAuthRepository(members: [.sample])

        await SignOutModel(auth: auth, session: AppSession(storage: InMemorySessionStorage())).signOut()

        #expect(await auth.revokedRefreshTokens.isEmpty)
    }
}
