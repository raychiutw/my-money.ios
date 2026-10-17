import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 帳戶頁公帳範圍的「家庭公帳待報銷總額」橫幅(上游 ADR 0015、#141)。
@MainActor
@Suite("待報銷總額橫幅")
struct PendingAdvancesBannerTests {
    private let advances = [InMemoryHouseholdRepository.myPendingAdvance, InMemoryHouseholdRepository.meiPendingAdvance]

    private func model(
        scope: AccountScope, households: InMemoryHouseholdRepository
    ) async -> AccountsModel {
        let model = AccountsModel(
            repository: InMemoryAccountRepository.sample(), dataVersion: DataVersion(), households: households, defaults: UserDefaults.isolated()
        )
        model.scope = scope
        await model.load()
        return model
    }

    @Test("公帳範圍:各成員待報銷加總(250 + 600)，有大於 0 才顯示橫幅")
    func totalsPendingAdvancesInHouseholdScope() async {
        let model = await model(scope: .household, households: .sample(advances: advances))

        #expect(model.pendingAdvanceTotal == Money(850))
        #expect(model.showsPendingAdvanceBanner)
        #expect(model.pendingAdvanceBannerText == "家庭公帳待報銷總額 $850")
    }

    @Test("有成員是公帳待抵扣(待報銷是負的)時不抵銷別人:只加總大於 0 的(600,不是 600 − 300)")
    func offsetPendingDoesNotCancelOthers() async {
        let model = await model(
            scope: .household,
            households: .sample(advances: [InMemoryHouseholdRepository.meiPendingAdvance, InMemoryHouseholdRepository.meiOffsetAdvance])
        )

        #expect(model.pendingAdvanceTotal == Money(600))
        #expect(model.pendingAdvanceBannerText == "家庭公帳待報銷總額 $600")
    }

    @Test("只有公帳待抵扣的成員、沒有別人待報銷:不顯示橫幅")
    func offsetOnlyHidesTheBanner() async {
        let model = await model(scope: .household, households: .sample(advances: [InMemoryHouseholdRepository.meiOffsetAdvance]))

        #expect(!model.showsPendingAdvanceBanner)
    }

    @Test("全部與私帳範圍沒有橫幅，而且不多問 API")
    func otherScopesDoNotAsk() async {
        for scope in [AccountScope.all, .personal] {
            let households = InMemoryHouseholdRepository.sample(advances: advances)
            let model = await model(scope: scope, households: households)

            #expect(model.pendingAdvanceTotal == nil && !model.showsPendingAdvanceBanner, "\(scope)")
            #expect(await households.advancesCallCount == 0, "\(scope) 不該取代墊統計")
        }
    }

    @Test("沒有待報銷、已結清、沒有加入家庭時不顯示橫幅")
    func hiddenWhenNothingPending() async {
        let settled = HouseholdAdvance(
            memberID: UserID("a"), memberName: "甲", totalAdvanced: Money(100), totalReimbursed: Money(100),
            pendingReimbursement: .zero, advanceItems: [], reimbursementItems: []
        )
        #expect(await !model(scope: .household, households: .sample(advances: [settled])).showsPendingAdvanceBanner)
        #expect(await !model(scope: .household, households: .sample(advances: [])).showsPendingAdvanceBanner)
        #expect(await !model(scope: .household, households: InMemoryHouseholdRepository(household: nil, advances: advances)).showsPendingAdvanceBanner)
    }

    @Test("取代墊統計失敗時不顯示橫幅，帳戶頁其他區塊照常")
    func failureKeepsTheRestOfThePage() async {
        let households = InMemoryHouseholdRepository.sample(advances: advances)
        await households.fail(with: .rejected("伺服器忙碌"))
        let model = await model(scope: .household, households: households)

        #expect(!model.showsPendingAdvanceBanner)
        #expect(model.phase == .loaded)
    }

    @Test("從公帳切到全部，橫幅跟著消失")
    func bannerGoesAwayWhenScopeChanges() async {
        let households = InMemoryHouseholdRepository.sample(advances: advances)
        let model = await model(scope: .household, households: households)
        #expect(model.showsPendingAdvanceBanner)

        model.scope = .all
        await model.load()

        #expect(!model.showsPendingAdvanceBanner)
    }
}
