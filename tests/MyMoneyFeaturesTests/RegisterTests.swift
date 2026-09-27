import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("註冊")
struct RegisterTests {
    private let storage = InMemorySessionStorage()

    private func filledModel(
        auth: InMemoryAuthRepository = InMemoryAuthRepository(members: [.sample]),
        session: AppSession? = nil
    ) -> RegisterModel {
        let model = RegisterModel(auth: auth, session: session ?? AppSession(storage: storage))
        model.name = "小美"
        model.email = "mei@example.com"
        model.password = "secret123"
        model.confirmation = "secret123"
        return model
    }

    @Test("註冊成功後直接進入 tab 外殼，用的是新帳號")
    func registerSucceeds() async {
        let session = AppSession(storage: storage)
        let model = filledModel(session: session)

        await model.submit()

        #expect(session.current?.user.name == "小美")
        #expect(session.current?.user.email == "mei@example.com")
    }

    @Test(
        "姓名、Email、密碼、確認密碼都填了才能送出",
        arguments: [
            ("", "mei@example.com", "secret123", "secret123"),
            ("小美", "", "secret123", "secret123"),
            ("小美", "mei@example.com", "", "secret123"),
            ("小美", "mei@example.com", "secret123", ""),
            ("  ", "mei@example.com", "secret123", "secret123"),
        ]
    )
    func allFieldsAreRequired(name: String, email: String, password: String, confirmation: String) {
        let model = RegisterModel(auth: InMemoryAuthRepository(members: []), session: AppSession(storage: storage))
        model.name = name
        model.email = email
        model.password = password
        model.confirmation = confirmation

        #expect(!model.canSubmit)
    }

    @Test("四個欄位都填了就能送出")
    func filledFormCanBeSubmitted() {
        #expect(filledModel().canSubmit)
    }

    @Test("兩次密碼不一致時提示，而且不送出")
    func mismatchedPasswordsAreRejectedBeforeSubmitting() async {
        let auth = InMemoryAuthRepository(members: [])
        let session = AppSession(storage: storage)
        let model = filledModel(auth: auth, session: session)
        model.confirmation = "secret124"

        await model.submit()

        #expect(model.errorMessage == "兩次密碼不一致")
        #expect(session.current == nil)
        #expect(await auth.registeredEmails.isEmpty)
    }

    @Test("密碼少於 6 個字元時提示，而且不送出")
    func shortPasswordIsRejectedBeforeSubmitting() async {
        let auth = InMemoryAuthRepository(members: [])
        let model = filledModel(auth: auth)
        model.password = "12345"
        model.confirmation = "12345"

        await model.submit()

        #expect(model.errorMessage == "密碼至少 6 個字元")
        #expect(await auth.registeredEmails.isEmpty)
    }

    @Test("兩次密碼不一致的提示優先於長度不足(跟 web 的檢查順序一樣)")
    func mismatchIsCheckedBeforeLength() async {
        let model = filledModel()
        model.password = "abc"
        model.confirmation = "abd"

        await model.submit()

        #expect(model.errorMessage == "兩次密碼不一致")
    }

    @Test("Email 已被使用時顯示後端的訊息，留在註冊頁")
    func emailTakenShowsBackendMessage() async {
        let session = AppSession(storage: storage)
        let model = filledModel(session: session)
        model.email = "family@example.com"

        await model.submit()

        #expect(model.errorMessage == "此 Email 已被使用")
        #expect(session.current == nil)
    }

    /// 請求沒送到 repository 時，`waitUntilReached()` 會一直等;設時間上限，讓它失敗而不是卡住。
    @Test("送出期間按鈕停用，文字改成「建立中…」", .timeLimit(.minutes(1)))
    func submittingDisablesButton() async {
        let gate = Gate()
        let model = filledModel(auth: InMemoryAuthRepository(members: [], gate: gate))
        #expect(model.submitTitle == "建立帳號")

        let submission = Task { await model.submit() }
        await gate.waitUntilReached()

        #expect(model.submitTitle == "建立中…")
        #expect(!model.canSubmit)

        await gate.open()
        await submission.value
        #expect(model.submitTitle == "建立帳號")
    }

    @Test("再次送出時先清掉上一次的錯誤訊息")
    func resubmittingClearsPreviousError() async {
        let model = filledModel()
        model.confirmation = "different"
        await model.submit()
        #expect(model.errorMessage != nil)

        model.confirmation = "secret123"
        await model.submit()

        #expect(model.errorMessage == nil)
    }
}
