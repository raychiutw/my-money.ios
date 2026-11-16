import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 沒有 App 自己的登入頁(#356):未登入就自動開系統登入視窗，關掉再開，其他錯誤停住並可重試。
@MainActor
@Suite("登入(系統登入視窗)")
struct LoginTests {
    private let storage = InMemorySessionStorage()
    private let auth = InMemoryAuthRepository(members: [.sample])

    @Test("未登入就自動開登入視窗,登入成功進入 tab 外殼")
    func appearingOpensSignInAutomatically() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(auth: auth, session: session)

        await model.appeared()

        #expect(await auth.signInRequests == [false])
        #expect(session.current?.user.name == "小明")
    }

    @Test("登入成功後重開 app,直接進入 tab 外殼")
    func signedInSessionSurvivesRelaunch() async {
        await LoginModel(auth: auth, session: AppSession(storage: storage)).appeared()

        let relaunched = AppSession(storage: storage)

        #expect(relaunched.current?.user.name == "小明")
    }

    @Test("使用者關掉登入視窗:不顯示錯誤，再開一次")
    func cancellingReopensSignIn() async {
        let session = AppSession(storage: storage)
        let closingTwice = InMemoryAuthRepository(members: [.sample], signInErrors: [CancellationError(), CancellationError(), nil])
        let model = LoginModel(auth: closingTwice, session: session)

        await model.appeared()

        #expect(await closingTwice.signInRequests == [false, false, false])
        #expect(model.errorMessage == nil)
        #expect(session.current?.user.name == "小明")
    }

    @Test("其他錯誤:停住並顯示後端的訊息,不再自動開;按「重試」再開")
    func otherErrorsStopUntilRetry() async {
        let session = AppSession(storage: storage)
        let failingOnce = InMemoryAuthRepository(members: [.sample], signInErrors: [RepositoryError.rejected("授權碼無效或已被使用")])
        let model = LoginModel(auth: failingOnce, session: session)

        await model.appeared()
        #expect(model.errorMessage == "授權碼無效或已被使用")
        #expect(session.current == nil)

        // 回到前景(scenePhase .active)也不自動重開。
        await model.appeared()
        #expect(await failingOnce.signInRequests == [false])

        await model.retry()
        #expect(await failingOnce.signInRequests == [false, false])
        #expect(model.errorMessage == nil)
        #expect(session.current?.user.name == "小明")
    }

    @Test("登入視窗開著時不重複開;重試時先清掉上一次的錯誤訊息")
    func submittingStateAndErrorReset() async {
        let gate = Gate()
        await gate.open()
        let failingOnce = InMemoryAuthRepository(members: [.sample], gate: gate, signInErrors: [RepositoryError.rejected("失敗")])
        let model = LoginModel(auth: failingOnce, session: AppSession(storage: storage))
        await model.appeared()
        #expect(model.errorMessage == "失敗")

        await gate.close()
        let submission = Task { await model.retry() }
        await gate.waitUntilReached()
        #expect(model.isSubmitting)
        #expect(model.errorMessage == nil)
        await model.appeared()
        #expect(await failingOnce.signInRequests == [false, false])

        await gate.open()
        await submission.value
        #expect(!model.isSubmitting)
    }

    @Test("登出後回到未登入,又自動開一次登入視窗")
    func signingOutReopensSignIn() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(auth: auth, session: session)
        await model.appeared()

        session.signOut()
        await model.appeared()

        #expect(await auth.signInRequests == [false, false])
        #expect(session.current != nil)
    }
}
