import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("登入")
struct LoginTests {
    private let storage = InMemorySessionStorage()
    private let auth = InMemoryAuthRepository(members: [.sample])

    @Test("登入成功後進入 tab 外殼")
    func loginSucceeds() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(auth: auth, session: session)
        model.email = "family@example.com"
        model.password = "secret123"

        await model.submit()

        #expect(session.current?.user.name == "小明")
    }

    @Test("登入成功後重開 app,直接進入 tab 外殼")
    func signedInSessionSurvivesRelaunch() async {
        let model = LoginModel(auth: auth, session: AppSession(storage: storage))
        model.email = "family@example.com"
        model.password = "secret123"
        await model.submit()

        let relaunched = AppSession(storage: storage)

        #expect(relaunched.current?.user.name == "小明")
    }

    @Test("登入失敗時顯示後端回傳的訊息，留在登入頁")
    func loginFailureShowsBackendMessage() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(auth: auth, session: session)
        model.email = "family@example.com"
        model.password = "wrong-password"

        await model.submit()

        #expect(model.errorMessage == "Email 或密碼錯誤")
        #expect(session.current == nil)
    }

    @Test(
        "Email 或密碼空白時不能送出",
        arguments: [("", ""), ("family@example.com", ""), ("", "secret123"), ("  ", "secret123")]
    )
    func emailAndPasswordAreRequired(email: String, password: String) {
        let model = LoginModel(auth: auth, session: AppSession(storage: storage))
        model.email = email
        model.password = password

        #expect(!model.canSubmit)
    }

    @Test("Email 和密碼都填了才能送出")
    func filledFormCanSubmit() {
        let model = LoginModel(auth: auth, session: AppSession(storage: storage))
        model.email = "family@example.com"
        model.password = "secret123"

        #expect(model.canSubmit)
    }

    @Test("送出期間按鈕停用，文字改成「登入中…」")
    func submittingDisablesButton() async {
        let gate = Gate()
        let model = LoginModel(
            auth: InMemoryAuthRepository(members: [.sample], gate: gate),
            session: AppSession(storage: storage)
        )
        model.email = "family@example.com"
        model.password = "secret123"
        #expect(model.submitTitle == "登入")

        let submission = Task { await model.submit() }
        await gate.waitUntilReached()

        #expect(model.submitTitle == "登入中…")
        #expect(!model.canSubmit)

        await gate.open()
        await submission.value
        #expect(model.submitTitle == "登入")
    }

    @Test("再次送出時先清掉上一次的錯誤訊息")
    func resubmittingClearsPreviousError() async {
        let gate = Gate()
        await gate.open()
        let model = LoginModel(
            auth: InMemoryAuthRepository(members: [.sample], gate: gate),
            session: AppSession(storage: storage)
        )
        model.email = "family@example.com"
        model.password = "wrong-password"
        await model.submit()
        #expect(model.errorMessage == "Email 或密碼錯誤")

        await gate.close()
        model.password = "secret123"
        let retry = Task { await model.submit() }
        await gate.waitUntilReached()

        #expect(model.errorMessage == nil)

        await gate.open()
        await retry.value
    }

    @Test("Email 前後的空白不算(鍵盤的自動完成會補上空白)")
    func emailIsTrimmed() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(auth: auth, session: session)
        model.email = " family@example.com "
        model.password = "secret123"

        await model.submit()

        #expect(session.current?.user.name == "小明")
    }

    @Test("密碼預設隱藏")
    func passwordIsHiddenByDefault() {
        let model = LoginModel(auth: auth, session: AppSession(storage: storage))

        #expect(!model.isPasswordVisible)
    }

    @Test("登出後回到的登入頁是空白的，密碼不留在記憶體裡")
    func loginFormIsBlankAfterSignOut() async {
        let session = AppSession(storage: storage)
        let model = LoginModel(auth: auth, session: session)
        model.email = "family@example.com"
        model.password = "secret123"
        model.isPasswordVisible = true
        await model.submit()

        session.signOut()

        #expect(model.email.isEmpty)
        #expect(model.password.isEmpty)
        #expect(!model.isPasswordVisible)
    }
}
