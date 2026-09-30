import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("儲蓄目標")
struct SavingsGoalsTests {
    private func loaded(
        _ repository: InMemorySavingsGoalRepository = .sample(),
        dataVersion: DataVersion = DataVersion()
    ) async -> SavingsGoalsModel {
        let model = SavingsGoalsModel(repository: repository, dataVersion: dataVersion)
        await model.load()
        return model
    }

    private func goal(target: Int, saved: Int) -> SavingsGoal {
        SavingsGoal(
            id: SavingsGoalID("x"), name: "x", emoji: "🎯", targetAmount: Money(Decimal(target)),
            savedAmount: Money(Decimal(saved)), monthlyReserve: .zero, deadline: nil
        )
    }

    @Test("三張統計卡：已存金額合計、目標金額合計與整體達成率、每月預留合計")
    func summaryCards() async {
        let model = await loaded()

        #expect(model.totalSaved == Money(4000))
        #expect(model.totalTarget == Money(161_000))
        // 4000 / 161000 = 2.48…%,取 1 位小數。
        #expect(model.overallRateText == "2.5%")
        #expect(model.totalMonthlyReserve == Money(5200))
    }

    /// 已存、目標分開顯示，百分比交給進度條;VoiceOver 念百分比(#77)。
    @Test("目標列 VoiceOver 念成一句：名稱、已存、目標、達成百分比、截止日，已達成時加註")
    func goalSpokenText() {
        let trip = SavingsGoal(
            id: SavingsGoalID("t"), name: "沖繩旅遊", emoji: "✈️", targetAmount: Money(60000),
            savedAmount: Money(3000), monthlyReserve: Money(5000), deadline: CalendarDay(year: 2027, month: 3, day: 31)
        )
        let done = SavingsGoal(
            id: SavingsGoalID("d"), name: "iOS 小目標", emoji: "🎒", targetAmount: Money(1000),
            savedAmount: Money(1000), monthlyReserve: .zero, deadline: nil
        )

        #expect(trip.spokenText(deadline: "2027年3月31日") == "沖繩旅遊，已存 3,000 元，目標 60,000 元，達成 5%，截止日 2027年3月31日")
        #expect(done.spokenText(deadline: nil) == "iOS 小目標，已存 1,000 元，目標 1,000 元，達成 100%，已達成目標")
    }

    @Test("沒有任何目標時，整體達成率顯示 0%")
    func overallRateWithoutGoals() async {
        let model = await loaded(InMemorySavingsGoalRepository(goals: []))

        #expect(model.overallRateText == "0%")
        #expect(model.datedGoals.isEmpty && model.undatedGoals.isEmpty)
    }

    @Test("分成有截止日和沒有截止日兩組")
    func groupsByDeadline() async {
        let model = await loaded()

        #expect(model.datedGoals.map(\.name) == ["沖繩旅遊", "iOS 小目標"])
        #expect(model.undatedGoals.map(\.name) == ["緊急備用金"])
    }

    /// 系統依地區的格式(DESIGN.md「日期」),不再是 web 的「2027/03/31」。跟今天同一年時省略年份。
    @Test("截止日是「2027年3月31日」這種系統格式，今年的省略年份")
    func deadlineText() async throws {
        let model = SavingsGoalsModel(
            repository: InMemorySavingsGoalRepository.sample(), dataVersion: DataVersion(), locale: Locale(identifier: "zh_Hant_TW"),
            today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )
        await model.load()

        #expect(model.datedGoals.map { model.deadlineText(of: $0) } == ["2027年3月31日", "12月31日"])
        let undated = try #require(model.undatedGoals.first)
        #expect(model.deadlineText(of: undated) == nil)
    }

    /// 已存金額可能超過目標金額：編輯時把目標金額調低，後端的 PUT 不會重新卡上限。
    @Test("目標卡片的百分比取整數，最多 100%", arguments: [
        (60000, 3000, "5%"),
        (1000, 1000, "100%"),
        (1000, 1500, "100%"),
        (3, 1, "33%"),
        (8, 1, "13%"),
    ])
    func percentText(target: Int, saved: Int, expected: String) {
        #expect(goal(target: target, saved: saved).percentText == expected)
    }

    @Test("已存金額達到目標金額就是已達成，不能再存入")
    func achievedGoalsCannotDeposit() async throws {
        let model = await loaded()
        let achieved = try #require(model.datedGoals.last)
        let trip = try #require(model.datedGoals.first)

        #expect(achieved.isAchieved)
        #expect(model.makeDeposit(for: achieved) == nil)
        #expect(model.makeDeposit(for: trip)?.title == "存入「✈️ 沖繩旅遊」")
    }

    @Test("刪除後資料版本遞增;確認文字包含名稱")
    func deleteBumpsDataVersion() async throws {
        let repository = InMemorySavingsGoalRepository.sample()
        let dataVersion = DataVersion()
        let model = await loaded(repository, dataVersion: dataVersion)
        let trip = try #require(model.datedGoals.first)

        #expect(model.deleteConfirmation(for: trip) == "確定要刪除儲蓄目標「沖繩旅遊」嗎？")
        await model.delete(trip)

        #expect(await repository.deletedIDs == [trip.id])
        #expect(dataVersion.value == 1)
    }

    @Test("資料版本改變後重抓")
    func refreshesOnDataVersionChange() async {
        let repository = InMemorySavingsGoalRepository.sample()
        let dataVersion = DataVersion()
        let model = await loaded(repository, dataVersion: dataVersion)
        let fetches = await repository.fetchCount

        await model.refreshIfStale()
        #expect(await repository.fetchCount == fetches)

        dataVersion.bump()
        await model.refreshIfStale()
        #expect(await repository.fetchCount > fetches)
    }
}

@MainActor
@Suite("存入儲蓄目標")
struct SavingsGoalDepositTests {
    private let repository = InMemorySavingsGoalRepository.sample()
    private let dataVersion = DataVersion()

    private func deposit() async throws -> SavingsGoalDepositModel {
        let model = SavingsGoalsModel(repository: repository, dataVersion: dataVersion)
        await model.load()
        let goal = try #require(model.datedGoals.first)
        return try #require(model.makeDeposit(for: goal))
    }

    @Test("顯示目前的已存金額和目標金額")
    func summary() async throws {
        let deposit = try await deposit()

        #expect(deposit.summary == "目前已存 $3,000 / 目標 $60,000")
    }

    @Test("金額要是正數", arguments: ["", "0", "-5", "abc", "1,000", "12.5"])
    func amountMustBePositive(amount: String) async throws {
        let deposit = try await deposit()
        deposit.amountText = amount

        #expect(!(await deposit.save()))

        #expect(deposit.errorMessage == "請輸入有效存款金額")
        #expect(await repository.deposits.isEmpty)
    }

    @Test("存入成功後資料版本遞增;已存金額以後端的結果為準(上限是目標金額)")
    func depositUsesBackendResult() async throws {
        let model = SavingsGoalsModel(repository: repository, dataVersion: dataVersion)
        await model.load()
        let trip = try #require(model.datedGoals.first)
        let deposit = try #require(model.makeDeposit(for: trip))
        deposit.amountText = "100000"

        #expect(await deposit.save())

        #expect(await repository.deposits == [.init(id: trip.id, amount: Money(100_000))])
        #expect(dataVersion.value == 1)
        await model.refreshIfStale()
        #expect(model.datedGoals.first?.savedAmount == Money(60000))
    }
}
