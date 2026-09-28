import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("登出與 session 過期")
struct SessionTests {
    private let storage = InMemorySessionStorage(session: Session(
        token: "stored-token",
        user: InMemoryAuthRepository.Member.sample.user
    ))

    @Test("登出後清掉 session,回到登入頁;重開 app 也要重新登入")
    func signOutClearsSession() {
        let session = AppSession(storage: storage)

        session.signOut()

        #expect(session.current == nil)
        #expect(AppSession(storage: storage).current == nil)
    }

    @Test("翻譯層通知 session 過期(非 /auth/* 回應 401)時清掉 session,回到登入頁")
    func expiredSessionReturnsToLogin() async {
        let session = AppSession(storage: storage)
        let seenByTranslationLayer: any SessionProvider = session

        await seenByTranslationLayer.sessionDidExpire()

        #expect(session.current == nil)
        #expect(AppSession(storage: storage).current == nil)
    }

    @Test("翻譯層拿到的是目前 session 的 token")
    func translationLayerGetsCurrentToken() async {
        let session = AppSession(storage: storage)
        let seenByTranslationLayer: any SessionProvider = session

        #expect(await seenByTranslationLayer.currentToken() == "stored-token")
        session.signOut()
        #expect(await seenByTranslationLayer.currentToken() == nil)
    }
}
