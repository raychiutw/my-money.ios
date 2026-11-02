import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 預測的累計結餘(上游 `a68a231`,#315)與透支風險區間(#316)。
@MainActor
@Suite("預測:事件累計結餘與透支風險區間")
struct ForecastOverdraftTests {
    private let day0 = CalendarDay(year: 2026, month: 11, day: 2)

    private func day(_ offset: Int) -> CalendarDay { day0.addingDays(offset) }

    private func forecast(balances: [Int], events: [ForecastEvent] = []) -> CashFlowForecast {
        CashFlowForecast(
            dailyBalances: balances.enumerated().map { DailyBalance(date: day($0.offset), balance: Money(Decimal($0.element))) },
            minBalance: Money(Decimal(balances.min() ?? 0)), minDate: day(0), willOverdraft: (balances.min() ?? 0) < 0, events: events
        )
    }

    private func model(_ forecast: CashFlowForecast) async -> ForecastModel {
        let model = ForecastModel(
            repository: InMemoryForecastRepository(
                forecast: forecast, check: { PurchaseCheck(amount: $0, verdict: .safe, minBalance: .zero, affectedGoalNames: []) }
            ),
            dataVersion: DataVersion(),
            defaults: UserDefaults(suiteName: "ForecastOverdraftTests.\(UUID().uuidString)")!,
            locale: Locale(identifier: "zh_Hant_TW"), today: { day0 }
        )
        await model.load()
        return model
    }

    // MARK: 累計結餘(#315)

    @Test("事件列顯示事件後的累計結餘;沒有(舊回應)就不顯示")
    func balanceAfterText() async {
        let m = await model(forecast(balances: [100]))
        let withBalance = ForecastEvent(date: day(0), name: "房租", type: .expense, amount: Money(12000), runningBalance: Money(89950))
        let negative = ForecastEvent(date: day(0), name: "繳卡費", type: .expense, amount: Money(5000), runningBalance: Money(-1200))
        let legacy = ForecastEvent(date: day(0), name: "舊", type: .expense, amount: Money(1))

        #expect(m.balanceAfterText(of: withBalance) == "結餘 $89,950")
        #expect(m.balanceAfterText(of: negative) == "結餘 −$1,200")
        #expect(m.balanceAfterText(of: legacy) == nil)
        #expect(!m.isOverdrawn(withBalance))
        #expect(m.isOverdrawn(negative))
        #expect(!m.isOverdrawn(legacy))
    }

    @Test("朗讀包含累計結餘;負的加「透支」")
    func spokenIncludesBalance() async {
        let m = await model(forecast(balances: [100]))
        let ok = ForecastEvent(date: day(0), name: "房租", type: .expense, amount: Money(12000), runningBalance: Money(89950))
        let negative = ForecastEvent(date: day(0), name: "繳卡費", type: .expense, amount: Money(5000), runningBalance: Money(-1200))

        #expect(m.spokenText(of: ok).hasSuffix("事件後結餘 89,950 元"))
        #expect(m.spokenText(of: negative).hasSuffix("事件後結餘 負 1,200 元,透支"))
    }

    // MARK: 透支風險區間(#316)

    @Test("全程為正:沒有透支區間")
    func noIntervals() async {
        #expect(await model(forecast(balances: [100, 50, 80])).overdraftIntervals.isEmpty)
    }

    @Test("單日為負:起訖同一天、共 1 天")
    func singleDay() async {
        let m = await model(forecast(balances: [100, -50, 20]))
        #expect(m.overdraftIntervals == [
            OverdraftInterval(start: day(1), end: day(1), days: 1, minBalance: Money(-50), minDate: day(1), triggerNames: [], startsNegative: false)
        ])
    }

    @Test("連續多日為負合成一段;區間最低餘額與發生日;兩段分開")
    func multipleIntervals() async {
        let m = await model(forecast(balances: [10, -5, -30, -10, 40, -1, 5]))
        #expect(m.overdraftIntervals.map(\.start) == [day(1), day(5)])
        #expect(m.overdraftIntervals.map(\.days) == [3, 1])
        #expect(m.overdraftIntervals[0].minBalance == Money(-30))
        #expect(m.overdraftIntervals[0].minDate == day(2))
    }

    @Test("第 0 天就是負的:標示起始可用餘額不足")
    func startsNegative() async {
        let m = await model(forecast(balances: [-10, -20, 5]))
        #expect(m.overdraftIntervals.first?.startsNegative == true)
    }

    @Test("區間首日的支出事件(未繳)列為觸發事件;已繳與收入不列")
    func triggers() async {
        let events = [
            ForecastEvent(date: day(1), name: "繳卡費", type: .expense, amount: Money(500)),
            ForecastEvent(date: day(1), name: "薪水", type: .income, amount: Money(1)),
            ForecastEvent(date: day(1), name: "已繳的", type: .expense, amount: Money(9), isSettled: true),
            ForecastEvent(date: day(2), name: "別天", type: .expense, amount: Money(9)),
        ]
        let m = await model(forecast(balances: [100, -50, -60, 5], events: events))
        #expect(m.overdraftIntervals.first?.triggerNames == ["繳卡費"])
    }

    @Test("點區間:查詢區間鎖到那一段;再還原整個期程")
    func focusAndReset() async {
        let m = await model(forecast(balances: [10, -5, -30, 40, 5]))
        let interval = m.overdraftIntervals[0]
        m.focus(on: interval)

        #expect(m.rangeStart == day(1))
        #expect(m.rangeEnd == day(2))
        #expect(m.focusedInterval == interval)
        m.resetRange()
        #expect(m.focusedInterval == nil)
    }

    @Test("文字:起訖與天數、區間最低餘額")
    func texts() async {
        let m = await model(forecast(balances: [10, -5, -30, 40]))
        let multi = m.overdraftIntervals[0]
        #expect(m.overdraftTitle(of: multi) == "11月3日~11月4日・共 2 天")
        #expect(m.overdraftDetail(of: multi) == "最低 −$30(11月4日)")
        let single = await model(forecast(balances: [10, -5, 40]))
        #expect(single.overdraftTitle(of: single.overdraftIntervals[0]) == "11月3日・共 1 天")
        #expect(m.overdraftSummary == "共 1 段透支(合計 2 天)")
    }
}
