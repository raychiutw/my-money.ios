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

    @Test("確認訊息說明資料全部刪除且無法復原，並提醒家庭管理員:建立家庭的人刪除帳號會連整個家庭一起刪除")
    func confirmationWarnsAboutHousehold() {
        let model = AccountDeletionModel(auth: InMemoryAuthRepository(members: [.sample]), session: signedInSession())

        #expect(model.confirmation.contains("無法復原"))
        #expect(model.confirmation.contains("家庭"))
    }
}
