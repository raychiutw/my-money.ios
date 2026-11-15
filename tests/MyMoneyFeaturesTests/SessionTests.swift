import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("登出與 session 過期")
struct SessionTests {
    private let storage = InMemorySessionStorage(session: Session(
        user: InMemoryAuthRepository.Member.sample.user,
        tokens: SessionTokens(access: "stored-token", refresh: "stored-refresh", accessExpiresAt: nil)
    ))

    @Test("登出後清掉 session,回到登入頁;重開 app 也要重新登入")
    func signOutClearsSession() {
        let session = AppSession(storage: storage)

        session.signOut()

        #expect(session.current == nil)
        #expect(AppSession(storage: storage).current == nil)
    }

    @Test("翻譯層通知 session 過期(401 帶 invalid_token)時清掉 session,回到登入頁")
    func expiredSessionReturnsToLogin() async {
        let session = AppSession(storage: storage)
        let seenByTranslationLayer: any SessionProvider = session

        await seenByTranslationLayer.sessionDidExpire()

        #expect(session.current == nil)
        #expect(AppSession(storage: storage).current == nil)
    }

    @Test("翻譯層拿到的是目前 session 的存取權杖")
    func translationLayerGetsCurrentToken() async {
        let session = AppSession(storage: storage)
        let seenByTranslationLayer: any SessionProvider = session

        #expect(await seenByTranslationLayer.currentTokens()?.access == "stored-token")
        session.signOut()
        #expect(await seenByTranslationLayer.currentTokens() == nil)
    }

    @Test("refresh 輪替後換成新的權杖並存到裝置上:重開 app 用新的更新權杖(#335)")
    func refreshedTokensAreSaved() async {
        let session = AppSession(storage: storage)
        let seenByTranslationLayer: any SessionProvider = session
        let rotated = SessionTokens(access: "new-access", refresh: "rotated-refresh", accessExpiresAt: nil)

        await seenByTranslationLayer.sessionDidRefresh(rotated)

        #expect(session.current?.tokens == rotated)
        #expect(session.current?.user == InMemoryAuthRepository.Member.sample.user)
        #expect(AppSession(storage: storage).current?.tokens.refresh == "rotated-refresh")
    }

    @Test("已經登出後才回來的 refresh 結果不會讓人重新登入")
    func refreshAfterSignOutIsIgnored() async {
        let session = AppSession(storage: storage)
        let seenByTranslationLayer: any SessionProvider = session
        session.signOut()

        await seenByTranslationLayer.sessionDidRefresh(
            SessionTokens(access: "new-access", refresh: "rotated-refresh", accessExpiresAt: nil)
        )

        #expect(session.current == nil)
        #expect(AppSession(storage: storage).current == nil)
    }

    @Test("結束原因旗標:過期後換人登入,旗標回到預設(不會把上一次的原因帶到下一個 session,code review)")
    func endReasonFlagsResetOnStart() async {
        let session = AppSession(storage: InMemorySessionStorage(session: nil))
        let sample = InMemoryAuthRepository.Member.sample.session
        session.start(sample)

        await session.sessionDidExpire()
        #expect(session.endedByExpiry)

        session.start(sample)
        #expect(!session.endedByExpiry)
        #expect(!session.endedByDeletion)
    }
}
