import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 查詢時先停在 gate,放行後跟 URLSession 一樣：工作已經被取消時丟出 `CancellationError`。
private struct GatedStatisticsRepository: StatisticsRepository {
    let gate: Gate
    let base: InMemoryStatisticsRepository

    func categoryExpenses(month: CalendarMonth, scope: ViewScope) async throws -> [CategoryExpense] {
        try await base.categoryExpenses(month: month, scope: scope)
    }

    func monthlySummaries(year: Int, scope: ViewScope) async throws -> [MonthlySummary] {
        await gate.pass()
        try Task.checkCancellation()
        return try await base.monthlySummaries(year: year, scope: scope)
    }

    func householdShares(month: CalendarMonth) async throws -> [HouseholdShare] {
        try await base.householdShares(month: month)
    }

    func budgets(month: CalendarMonth) async throws -> [Budget] {
        try await base.budgets(month: month)
    }

    func setBudget(_ amount: Money, for category: TransactionCategory, month: CalendarMonth) async throws {
        try await base.setBudget(amount, for: category, month: month)
    }
}

/// `.task(id:)` 在月份或視角改變時取消前一次載入;下拉更新的載入可能比新的載入晚回來。
@MainActor
@Suite("載入被取消或過期時不蓋掉畫面")
struct LoadingRaceTests {
    private let september = CalendarMonth(year: 2026, month: 9)
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func statistics(_ gate: Gate) -> StatisticsModel {
        StatisticsModel(
            repository: GatedStatisticsRepository(gate: gate, base: .sample(month: september)),
            dataVersion: DataVersion(), today: { today }
        )
    }

    @Test("統計：被取消的載入不顯示成載入失敗", .timeLimit(.minutes(1)))
    func cancelledStatisticsLoad() async {
        let gate = Gate()
        let model = statistics(gate)

        let loading = Task { await model.load() }
        await gate.waitUntilReached()
        loading.cancel()
        await gate.open()
        await loading.value

        #expect(model.phase == .loading)
    }

    @Test("統計：換了月份之後才回來的舊結果不套用", .timeLimit(.minutes(1)))
    func staleStatisticsLoad() async {
        let gate = Gate()
        let model = statistics(gate)

        let loading = Task { await model.load() }
        await gate.waitUntilReached()
        model.month = september.next
        await gate.open()
        await loading.value

        #expect(model.phase == .loading)
        #expect(model.categoryExpenses.isEmpty)
    }

    @Test("總覽：被取消的載入不顯示成載入失敗", .timeLimit(.minutes(1)))
    func cancelledOverviewLoad() async throws {
        let gate = Gate()
        let suite = "LoadingRaceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OverviewModel(
            accounts: InMemoryAccountRepository.sample(),
            transactions: InMemoryTransactionRepository(transactions: SampleTransactions.make(today: today)),
            statistics: GatedStatisticsRepository(gate: gate, base: .sample(month: september)),
            goals: InMemorySavingsGoalRepository.sample(),
            dataVersion: DataVersion(), defaults: defaults, today: { today }
        )

        let loading = Task { await model.load() }
        await gate.waitUntilReached()
        loading.cancel()
        await gate.open()
        await loading.value

        #expect(model.phase == .loading)
        #expect(model.summary == nil)
    }
}
