import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("現金流預測與購買力試算")
struct ForecastTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func loaded(_ repository: InMemoryForecastRepository? = nil) async -> (ForecastModel, InMemoryForecastRepository) {
        let repository = repository ?? InMemoryForecastRepository.sample(today: today)
        let model = ForecastModel(repository: repository, dataVersion: DataVersion())
        await model.load()
        return (model, repository)
    }

    private func forecast(overdraft: Bool, minDate: CalendarDay?) -> CashFlowForecast {
        CashFlowForecast(
            dailyBalances: [DailyBalance(date: today, balance: Money(100))],
            minBalance: overdraft ? Money(-500) : Money(100),
            minDate: minDate,
            willOverdraft: overdraft,
            events: []
        )
    }

    @Test("資料回來之前沒有預測(畫面不會先顯示「安全」或 $0)")
    func nothingBeforeLoading() {
        let model = ForecastModel(repository: InMemoryForecastRepository.sample(today: today), dataVersion: DataVersion())

        #expect(model.phase == .loading)
        #expect(model.forecast == nil)
    }

    @Test("載入失敗時也沒有預測")
    func nothingAfterFailure() async {
        let repository = InMemoryForecastRepository.sample(today: today)
        await repository.fail(with: .rejected("伺服器錯誤"))

        let (model, _) = await loaded(repository)

        #expect(model.phase == .failed("伺服器錯誤"))
        #expect(model.forecast == nil)
    }

    @Test("透支風險的標題", arguments: [(true, "存在透支風險"), (false, "現金流充裕安全")])
    func riskTitle(overdraft: Bool, expected: String) {
        #expect(forecast(overdraft: overdraft, minDate: today).riskTitle == expected)
    }

    @Test("最低餘額的發生日期;沒有變動時顯示「無變動」")
    func minDateText() {
        #expect(forecast(overdraft: false, minDate: CalendarDay(year: 2026, month: 10, day: 5)).minDateText == "2026/10/05")
        #expect(forecast(overdraft: false, minDate: nil).minDateText == "無變動")
    }

    @Test("預定收支依後端的順序")
    func events() async throws {
        let (model, _) = await loaded()
        let forecast = try #require(model.forecast)

        #expect(forecast.events.map(\.name) == ["房租", "薪水"])
        #expect(forecast.dailyBalances.count == 30)
    }

    @Test("購買力試算的金額要是正數", arguments: ["", "0", "-1", "abc", "1,000", "12.5"])
    func checkRequiresPositiveAmount(amount: String) async {
        let (model, repository) = await loaded()
        model.purchaseAmountText = amount

        await model.checkPurchase()

        #expect(model.purchaseError == "請輸入有效的購買金額")
        #expect(model.purchaseCheck == nil)
        #expect(await repository.checkedAmounts.isEmpty)
    }

    @Test("改成無效的金額時，清掉上一次的試算結果")
    func invalidAmountClearsPreviousResult() async {
        let (model, _) = await loaded()
        model.purchaseAmountText = "1000"
        await model.checkPurchase()
        #expect(model.purchaseCheck != nil)

        model.purchaseAmountText = "abc"
        await model.checkPurchase()

        #expect(model.purchaseCheck == nil)
        #expect(model.purchaseError == "請輸入有效的購買金額")
    }

    @Test("試算結果", arguments: [
        (1000, PurchaseVerdict.safe),
        (50000, .caution),
        (60000, .danger),
    ])
    func checkPurchase(amount: Int, verdict: PurchaseVerdict) async throws {
        let (model, repository) = await loaded()
        model.purchaseAmountText = "\(amount)"

        await model.checkPurchase()

        #expect(await repository.checkedAmounts == [Money(Decimal(amount))])
        #expect(model.purchaseCheck?.verdict == verdict)
        #expect(model.purchaseError == nil)
    }

    @Test("放心購買：顯示金額和最低餘額")
    func safeMessage() {
        let check = PurchaseCheck(amount: Money(1000), verdict: .safe, minBalance: Money(52440), affectedGoalNames: ["沖繩旅遊"])

        #expect(check.title == "放心購買")
        #expect(check.message == "花 $1,000 之後，未來 30 天的最低餘額仍有 $52,440,也不影響儲蓄目標的每月預留。")
    }

    @Test("審慎評估：列出受影響的儲蓄目標，用「、」串接")
    func cautionMessage() {
        let check = PurchaseCheck(amount: Money(50000), verdict: .caution, minBalance: Money(3440), affectedGoalNames: ["沖繩旅遊", "緊急備用金"])

        #expect(check.title == "審慎評估")
        #expect(check.message == "花 $50,000 不會透支，但會壓縮儲蓄目標的每月預留(可能影響沖繩旅遊、緊急備用金)。建議延後購買或調降金額。")
    }

    @Test("不建議購買：顯示最低餘額")
    func dangerMessage() {
        let check = PurchaseCheck(amount: Money(60000), verdict: .danger, minBalance: Money(-6560), affectedGoalNames: [])

        #expect(check.title == "不建議購買")
        #expect(check.message == "花 $60,000 之後，未來 30 天的餘額最低會跌到 -$6,560。")
    }

    @Test("試算失敗時顯示後端的訊息")
    func checkFailure() async {
        let (model, repository) = await loaded()
        await repository.fail(with: .rejected("請輸入有效金額"))
        model.purchaseAmountText = "100"

        await model.checkPurchase()

        #expect(model.purchaseError == "請輸入有效金額")
        #expect(model.purchaseCheck == nil)
    }

    @Test("資料版本改變後重抓(固定收支、資金帳戶或儲蓄目標改了，預測就會變)")
    func refreshesOnDataVersionChange() async {
        let dataVersion = DataVersion()
        let repository = InMemoryForecastRepository.sample(today: today)
        let model = ForecastModel(repository: repository, dataVersion: dataVersion)
        await model.load()
        let fetches = await repository.fetchCount

        await model.refreshIfStale()
        #expect(await repository.fetchCount == fetches)

        dataVersion.bump()
        await model.refreshIfStale()
        #expect(await repository.fetchCount > fetches)
    }
}
