import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("登入後的畫面跟著 session 建立")
struct SignedInScreensTests {
    private func session(_ id: String) -> Session {
        Session(token: "token-\(id)", user: User(id: UserID(id), email: "\(id)@example.com", name: id))
    }

    private func makeScreens() -> SignedInScreens {
        SignedInScreens { MainScreens(accounts: AccountsModel(repository: InMemoryAccountRepository.sample())) }
    }

    @Test("同一個人的 session 更新時，沿用同一份畫面(不重抓資料)")
    func sameUserKeepsScreens() throws {
        let screens = makeScreens()
        screens.update(for: session("mei"))
        let first = try #require(screens.current?.accounts)

        screens.update(for: session("mei"))

        #expect(screens.current?.accounts === first)
    }

    @Test("換成另一個人登入時，建立新的畫面，不會看到上一個人的資料")
    func differentUserGetsFreshScreens() throws {
        let screens = makeScreens()
        screens.update(for: session("mei"))
        let first = try #require(screens.current?.accounts)

        screens.update(for: nil)
        screens.update(for: session("ming"))

        #expect(screens.current != nil)
        #expect(screens.current?.accounts !== first)
    }

    @Test("登出時丟掉畫面")
    func signOutDropsScreens() {
        let screens = makeScreens()
        screens.update(for: session("mei"))
        #expect(screens.current != nil)

        screens.update(for: nil)

        #expect(screens.current == nil)
    }
}
