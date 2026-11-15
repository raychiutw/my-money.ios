import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("登入(系統登入視窗)")
struct LoginTests {
    private let storage = InMemorySessionStorage()
    private let auth = InMemoryAuthRepository(members: [.sample])

    @Test("登入成功後進入 tab 外殼")
    func signInSucceeds() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(auth: auth, session: session)

        await model.signIn()

        #expect(session.current?.user.name == "小明")
        #expect(await auth.signInRequests == [false])
    }

    @Test("登入成功後重開 app,直接進入 tab 外殼")
    func signedInSessionSurvivesRelaunch() async {
        await LoginModel(auth: auth, session: AppSession(storage: storage)).signIn()

        let relaunched = AppSession(storage: storage)

        #expect(relaunched.current?.user.name == "小明")
    }

    @Test("關掉登入視窗:回到登入頁,不顯示錯誤")
    func cancellingShowsNoError() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(
            auth: InMemoryAuthRepository(members: [.sample], signInError: CancellationError()), session: session
        )

        await model.signIn()

        #expect(model.errorMessage == nil)
        #expect(session.current == nil)
        #expect(!model.isSubmitting)
    }

    @Test("登入失敗時顯示後端回傳的訊息，留在登入頁")
    func signInFailureShowsBackendMessage() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(
            auth: InMemoryAuthRepository(members: [.sample], signInError: RepositoryError.rejected("授權碼無效或已被使用")),
            session: session
        )

        await model.signIn()

        #expect(model.errorMessage == "授權碼無效或已被使用")
        #expect(session.current == nil)
    }

    @Test("登入期間按鈕停用;再次登入時先清掉上一次的錯誤訊息")
    func submittingStateAndErrorReset() async {
        let gate = Gate()
        await gate.open()
        let failing = LoginModel(
            auth: InMemoryAuthRepository(members: [.sample], signInError: RepositoryError.rejected("失敗")),
            session: AppSession(storage: storage)
        )
        await failing.signIn()
        #expect(failing.errorMessage == "失敗")

        let model = LoginModel(auth: InMemoryAuthRepository(members: [.sample], gate: gate), session: AppSession(storage: storage))
        await gate.close()
        let submission = Task { await model.signIn() }
        await gate.waitUntilReached()
        #expect(model.isSubmitting)
        #expect(model.errorMessage == nil)

        await gate.open()
        await submission.value
        #expect(!model.isSubmitting)
    }

    @Test("登入頁一出現就自動開登入視窗,登入成功進入 tab 外殼")
    func appearingOpensSignInAutomatically() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(auth: auth, session: session)

        await model.appeared()

        #expect(await auth.signInRequests == [false])
        #expect(session.current?.user.name == "小明")
    }

    @Test("關掉自動開的登入視窗後,登入頁再出現也不再自動開;按「登入」可以重開")
    func cancellingStopsAutoOpenButButtonReopens() async {
        let cancelling = InMemoryAuthRepository(members: [.sample], signInError: CancellationError())
        let model = LoginModel(auth: cancelling, session: AppSession(storage: storage))

        await model.appeared()
        await model.appeared()
        #expect(await cancelling.signInRequests == [false])
        #expect(model.errorMessage == nil)

        await model.signIn()
        #expect(await cancelling.signInRequests == [false, false])
    }

    @Test("登出後回到登入頁,又自動開一次登入視窗")
    func signingOutReenablesAutoOpen() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(auth: auth, session: session)
        await model.appeared()

        session.signOut()
        await model.appeared()

        #expect(await auth.signInRequests == [false, false])
        #expect(session.current != nil)
    }

    @Test("關掉自動開(UI 測試預設)時,登入頁出現不開登入視窗")
    func autoOpenCanBeTurnedOff() async {
        let model = LoginModel(auth: auth, session: AppSession(storage: storage), opensSignInOnAppear: false)

        await model.appeared()

        #expect(await auth.signInRequests.isEmpty)
    }
}
