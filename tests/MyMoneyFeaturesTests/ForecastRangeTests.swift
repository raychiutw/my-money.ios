import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 預測的起訖日期區間篩選(上游 `aecab6b`、#277):預設是整個 12 個月;改區間時最低餘額、透支風險、預定收支筆數、
/// 走勢圖與清單一起連動。範例預測:今天起第 7 天房租 −12,000(起始 65,440 → 53,440),第 27 天薪水 +45,000(→ 98,440)。
@MainActor
@Suite("預測區間篩選")
struct ForecastRangeTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func plus(_ days: Int) -> CalendarDay { today.addingDays(days) }

    /// 每個測試自己的 UserDefaults(視角會記在裡面，不能寫進共用的 `.standard` 影響別的測試)。
    private func loaded() async -> ForecastModel {
        let suite = "ForecastRangeTests-\(UUID().uuidString)"
        let model = ForecastModel(
            repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion(),
            defaults: UserDefaults(suiteName: suite)!, today: { today }
        )
        await model.load()
        return model
    }

    @Test("預設是整個期程:用後端的最低餘額、日期與筆數,沒有篩選中")
    func defaultIsFullRange() async throws {
        let model = await loaded()
        let forecast = try #require(model.forecast)

        #expect(!model.isRangeFiltered)
        #expect(model.visibleDailyBalances.count == ForecastHorizon.days)
        #expect(model.visibleEvents.count == 2)
        #expect(model.visibleMinBalance == forecast.minBalance)
        #expect(model.visibleMinDate == forecast.minDate)
        #expect(model.visibleWillOverdraft == forecast.willOverdraft)
    }

    @Test("縮小區間:走勢、預定收支、最低餘額與日期都只看區間內")
    func narrowedRange() async {
        let model = await loaded()

        model.rangeStart = plus(30)
        model.rangeEnd = plus(40)

        #expect(model.isRangeFiltered)
        #expect(model.visibleDailyBalances.count == 11)
        #expect(model.visibleEvents.isEmpty, "區間內沒有預定收支")
        #expect(model.visibleMinBalance == Money(98440), "房租與薪水都在區間之前,區間內的餘額是 98,440")
        #expect(model.visibleMinDate == plus(30))
    }

    @Test("區間含房租:最低餘額是房租之後的 53,440,事件只有房租")
    func rangeWithRent() async {
        let model = await loaded()

        model.rangeStart = plus(0)
        model.rangeEnd = plus(20)

        #expect(model.visibleEvents.map(\.name) == ["房租"])
        #expect(model.visibleMinBalance == Money(53440))
        #expect(model.visibleMinDate == plus(7))
        #expect(!model.visibleWillOverdraft)
    }

    @Test("迄日不早於起日:起日改到迄日之後,迄日跟著起日")
    func endNeverBeforeStart() async {
        let model = await loaded()
        model.rangeEnd = plus(10)

        model.rangeStart = plus(20)

        #expect(model.rangeEnd == plus(20))
    }

    @Test("重設回到整個期程")
    func reset() async {
        let model = await loaded()
        model.rangeStart = plus(30)
        model.rangeEnd = plus(40)

        model.resetRange()

        #expect(!model.isRangeFiltered)
        #expect(model.visibleDailyBalances.count == ForecastHorizon.days)
    }

    @Test("換視角重新載入後區間回到整個期程")
    func scopeChangeResets() async {
        let model = await loaded()
        model.rangeStart = plus(30)

        model.scope = .household
        await model.load()

        #expect(!model.isRangeFiltered)
    }
}
