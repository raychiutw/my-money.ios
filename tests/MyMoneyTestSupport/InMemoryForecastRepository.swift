import Foundation
import MyMoneyDomain

/// 不連網路的現金流預測與購買力試算，記下每一次試算的金額。
public actor InMemoryForecastRepository: ForecastRepository {
    private let stored: CashFlowForecast
    private let check: @Sendable (Money) -> PurchaseCheck
    private var failure: RepositoryError?

    public private(set) var checkedAmounts: [Money] = []

    /// `forecast()` 被呼叫的次數，用來確認有沒有重抓。
    public private(set) var fetchCount = 0

    public init(forecast: CashFlowForecast, check: @escaping @Sendable (Money) -> PurchaseCheck) {
        stored = forecast
        self.check = check
    }

    /// 以台灣時間的今天產生(給 `-uiTesting` 的 composition root 用)。
    public static func sampleForToday() -> InMemoryForecastRepository {
        sample(today: CalendarDay.today())
    }

    /// 起始餘額 65440;第 8 天房租 -12000,第 28 天薪水 +45000(跟 prod 的 fixture 同樣的形狀)。
    /// 試算：超過 53440 會透支(不建議購買),超過 45440 會壓縮沖繩旅遊的每月預留(審慎評估)。
    public static func sample(today: CalendarDay) -> InMemoryForecastRepository {
        let rent = ForecastEvent(date: day(today, plus: 7), name: "房租", type: .expense, amount: Money(12000))
        let salary = ForecastEvent(date: day(today, plus: 27), name: "薪水", type: .income, amount: Money(45000))
        var balance = Money(65440)
        let dailyBalances = (0..<30).map { offset in
            let date = day(today, plus: offset)
            for event in [rent, salary] where event.date == date {
                balance = event.type == .income ? balance + event.amount : balance - event.amount
            }
            return DailyBalance(date: date, balance: balance)
        }
        let forecast = CashFlowForecast(
            dailyBalances: dailyBalances, minBalance: Money(53440), minDate: rent.date, willOverdraft: false, events: [rent, salary]
        )
        return InMemoryForecastRepository(forecast: forecast) { amount in
            let minBalance = Money(53440) - amount
            let verdict: PurchaseVerdict = minBalance < .zero ? .danger : (Money(45440) < amount ? .caution : .safe)
            return PurchaseCheck(amount: amount, verdict: verdict, minBalance: minBalance, affectedGoalNames: ["沖繩旅遊"])
        }
    }

    /// 截圖巡覽用(`-uiTestingOverdraftForecast`):起始餘額 20000,第 8 天房租 -35000 會透支，第 28 天薪水 +45000 回到正數，
    /// 走勢圖才看得到跨過零線的紅色段落(#116)。
    public static func overdraftSampleForToday() -> InMemoryForecastRepository {
        let today = CalendarDay.today()
        let rent = ForecastEvent(date: day(today, plus: 7), name: "房租", type: .expense, amount: Money(35000))
        let salary = ForecastEvent(date: day(today, plus: 27), name: "薪水", type: .income, amount: Money(45000))
        var balance = Money(20000)
        let dailyBalances = (0..<30).map { offset in
            let date = day(today, plus: offset)
            for event in [rent, salary] where event.date == date {
                balance = event.type == .income ? balance + event.amount : balance - event.amount
            }
            return DailyBalance(date: date, balance: balance)
        }
        let forecast = CashFlowForecast(
            dailyBalances: dailyBalances, minBalance: Money(-15000), minDate: rent.date, willOverdraft: true, events: [rent, salary]
        )
        return InMemoryForecastRepository(forecast: forecast) { amount in
            PurchaseCheck(amount: amount, verdict: .danger, minBalance: Money(-15000) - amount, affectedGoalNames: [])
        }
    }

    public func forecast() async throws -> CashFlowForecast {
        fetchCount += 1
        if let failure { throw failure }
        return stored
    }

    public func checkPurchase(_ amount: Money) async throws -> PurchaseCheck {
        if let failure { throw failure }
        checkedAmounts.append(amount)
        return check(amount)
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    private static func day(_ day: CalendarDay, plus offset: Int) -> CalendarDay {
        CalendarDay(date: day.startOfDay.addingTimeInterval(TimeInterval(offset * 86_400 + 43_200)))
    }
}
