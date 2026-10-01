import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("家庭頁數字優先:分攤建議、各成員代墊、我的代墊數字(#121)")
struct HouseholdNumbersTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let me = InMemoryAuthRepository.Member.sample.user.id

    private func loaded(
        advances: [HouseholdAdvance] = [InMemoryHouseholdRepository.myPendingAdvance, InMemoryHouseholdRepository.meiPendingAdvance],
        statistics: InMemoryStatisticsRepository? = InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 9)),
        household: InMemoryHouseholdRepository? = nil
    ) async -> HouseholdModel {
        let model = HouseholdModel(
            repository: household ?? .sample(advances: advances), accounts: InMemoryAccountRepository.sample(),
            statistics: statistics, currentUser: me, dataVersion: DataVersion(), today: { today }
        )
        await model.load()
        return model
    }

    @Test("各成員本月的公帳代墊來自統計的後端值;分攤建議用同一份(差額的一半)")
    func sharesAndSettlement() async throws {
        let statistics = InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 9))
        let model = await loaded(statistics: statistics)

        #expect(model.shares.map(\.userName) == ["小明", "小美"])
        #expect(model.shares.map(\.total) == [Money(6000), Money(4000)])
        let settlement = try #require(model.settlement)
        #expect(settlement.perPerson == Money(5000))
        #expect(settlement.transfer?.from == "小美")
        #expect(settlement.transfer?.to == "小明")
        #expect(settlement.transfer?.amount == Money(1000))
        // 查的是今天所在的月份。
        #expect(await statistics.shareQueries == [CalendarMonth(year: 2026, month: 9)])
    }

    @Test("長條圖的平均線:各成員代墊的平均(只是顯示，分攤建議才是轉帳金額)")
    func averageShare() async {
        let model = await loaded()

        #expect(model.averageShare == Money(5000))
    }

    @Test("沒有統計資料來源，或統計取得失敗時，沒有分攤建議與長條圖，家庭頁照常載入")
    func noSharesWhenUnavailable() async {
        let none = await loaded(statistics: nil)
        #expect(none.shares.isEmpty && none.settlement == nil && none.averageShare == nil)
        #expect(none.phase == .loaded)

        let failing = InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 9))
        await failing.fail(with: .rejected("伺服器忙碌"))
        let failed = await loaded(statistics: failing)
        #expect(failed.shares.isEmpty && failed.settlement == nil)
        #expect(failed.phase == .loaded)
        #expect(!failed.advances.isEmpty)
    }

    @Test("還沒加入家庭時不查統計")
    func noSharesWithoutHousehold() async {
        let statistics = InMemoryStatisticsRepository.sample(month: CalendarMonth(year: 2026, month: 9))
        let model = await loaded(statistics: statistics, household: InMemoryHouseholdRepository(household: nil))

        #expect(model.shares.isEmpty)
        #expect(await statistics.shareQueries.isEmpty)
    }

    @Test("我的累計代墊、已報銷、待報銷:登入的人在代墊統計裡的那一筆(後端的值)")
    func myAdvance() async throws {
        let model = await loaded()

        let mine = try #require(model.myAdvance)
        #expect(mine.memberID == me)
        #expect(mine.totalAdvanced == Money(250))
        #expect(mine.totalReimbursed == .zero)
        #expect(mine.pendingReimbursement == Money(250))
    }

    @Test("代墊統計裡沒有我的紀錄時，沒有我的數字磚")
    func noMyAdvance() async {
        let model = await loaded(advances: [InMemoryHouseholdRepository.meiPendingAdvance])

        #expect(model.myAdvance == nil)
    }

    @Test("成員列顯示身分:管理員或一般成員(CONTEXT.md 的詞彙)")
    func roleTitles() async throws {
        let model = await loaded()

        let household = try #require(model.household)
        #expect(household.members.map { model.roleTitle(of: $0.userID) } == ["管理員", "一般成員"])
    }
}
