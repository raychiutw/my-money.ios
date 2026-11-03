import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("刪除帳號")
struct AccountDeletionTests {
    private let storage = InMemorySessionStorage()

    private func signedInSession() -> AppSession {
        let session = AppSession(storage: storage)
        session.start(Session(token: "t", user: InMemoryAuthRepository.Member.sample.user))
        return session
    }

    @Test("刪除成功後登出、回到登入頁")
    func deleteSignsOut() async {
        let session = signedInSession()
        let model = AccountDeletionModel(auth: InMemoryAuthRepository(members: [.sample]), session: session)

        await model.delete()

        #expect(session.current == nil)
        #expect(model.errorMessage == nil)
    }

    @Test("後端拒絕時不登出，顯示後端的訊息")
    func deleteFailureKeepsSession() async {
        let session = signedInSession()
        let auth = InMemoryAuthRepository(members: [.sample], deletionError: .rejected("帳號不存在"))
        let model = AccountDeletionModel(auth: auth, session: session)

        await model.delete()

        #expect(session.current != nil)
        #expect(model.errorMessage == "帳號不存在")
    }

    @Test("確認訊息說明資料全部刪除且無法復原;家庭的管理權會自動移交,只有最後一位成員才會連家庭一起刪除(上游 ADR 0035,#324)")
    func confirmationDescribesHouseholdSuccession() {
        let model = AccountDeletionModel(auth: InMemoryAuthRepository(members: [.sample]), session: signedInSession())

        #expect(model.confirmation == "刪除帳號會永久刪除你的帳戶、收支明細、儲蓄目標等所有個人資料，無法復原。如果家庭裡還有其他成員，管理權會自動交給下一位成員；如果你是最後一位成員，家庭也會一併刪除。")
        #expect(!model.confirmation.contains("成員關係也會一併刪除"), "舊的說法(整個家庭連帶刪除)已經不對")
    }
}
