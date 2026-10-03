import Foundation
import MyMoneyDomain

/// 不連網路的現金流預測與購買力試算，記下每一次試算的金額。
public actor InMemoryForecastRepository: ForecastRepository {
    private let stored: [ViewScope: CashFlowForecast]
    private let check: @Sendable (Money, ViewScope) -> PurchaseCheck
    private let gate: Gate?
    private var failure: RepositoryError?

    public private(set) var checkedAmounts: [Money] = []
    /// 每次試算帶的視角，用來確認一律明確帶 `scope`。
    public private(set) var checkedScopes: [ViewScope] = []
    /// 每次查詢預測帶的視角。
    public private(set) var requestedScopes: [ViewScope] = []

    /// `forecast(scope:)` 被呼叫的次數，用來確認有沒有重抓。
    public private(set) var fetchCount = 0

    /// 每個視角各自的預測(後端依視角算)。`gate`:查詢停在這裡直到放行(觀察換視角時舊回應被丟掉)。
    public init(
        forecasts: [ViewScope: CashFlowForecast], gate: Gate? = nil, check: @escaping @Sendable (Money, ViewScope) -> PurchaseCheck
    ) {
        stored = forecasts
        self.gate = gate
        self.check = check
    }

    /// 三個視角都是同一份預測。
    public init(forecast: CashFlowForecast, check: @escaping @Sendable (Money) -> PurchaseCheck) {
        stored = Dictionary(uniqueKeysWithValues: ViewScope.allCases.map { ($0, forecast) })
        gate = nil
        self.check = { amount, _ in check(amount) }
    }

    /// 以台灣時間的今天產生(給 `-uiTesting` 的 composition root 用)。
    public static func sampleForToday() -> InMemoryForecastRepository {
        sample(today: CalendarDay.today())
    }

    /// 全部:起始餘額 65440;第 8 天房租 -12000,第 28 天薪水 +45000(跟 prod 的 fixture 同樣的形狀)。
    /// 試算：超過 53440 會透支(不建議購買),超過 45440 會壓縮沖繩旅遊的每月預留(審慎評估)。
    /// 家庭公帳:起始餘額 30000,只有房租 -12000,最低餘額 18000;個人私帳:起始餘額 35440,只有薪水 +45000,最低餘額 35440。
    /// 公帳視角的試算不檢核個人儲蓄目標(跟後端一樣)。
    public static func sample(today: CalendarDay) -> InMemoryForecastRepository {
        func build(start: Int, _ events: [ForecastEvent]) -> CashFlowForecast {
            var balance = Money(Decimal(start))
            let dailyBalances = (0..<30).map { offset in
                let date = day(today, plus: offset)
                for event in events where event.date == date {
                    balance = event.type == .income ? balance + event.amount : balance - event.amount
                }
                return DailyBalance(date: date, balance: balance)
            }
            let low = dailyBalances.min { $0.balance < $1.balance }
            return CashFlowForecast(
                dailyBalances: dailyBalances, minBalance: low?.balance ?? .zero,
                minDate: dailyBalances.first { $0.balance == low?.balance }?.date,
                willOverdraft: (low?.balance ?? .zero) < .zero, events: events
            )
        }
        let rent = ForecastEvent(date: day(today, plus: 7), name: "房租", type: .expense, amount: Money(12000))
        let salary = ForecastEvent(date: day(today, plus: 27), name: "薪水", type: .income, amount: Money(45000))
        let forecasts: [ViewScope: CashFlowForecast] = [
            .all: build(start: 65440, [rent, salary]),
            .household: build(start: 30000, [rent]),
            .personal: build(start: 35440, [salary]),
        ]
        return InMemoryForecastRepository(forecasts: forecasts) { amount, scope in
            let minBalance = (forecasts[scope]?.minBalance ?? .zero) - amount
            let caution = scope == .all && Money(45440) < amount
            let verdict: PurchaseVerdict = minBalance < .zero ? .danger : (caution ? .caution : .safe)
            return PurchaseCheck(
                amount: amount, verdict: verdict, minBalance: minBalance, affectedGoalNames: scope == .household ? [] : ["沖繩旅遊"]
            )
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

    public func forecast(scope: ViewScope) async throws -> CashFlowForecast {
        fetchCount += 1
        requestedScopes.append(scope)
        await gate?.pass()
        if gate != nil { try Task.checkCancellation() }
        if let failure { throw failure }
        return stored[scope] ?? stored[.all]!
    }

    public func checkPurchase(_ amount: Money, scope: ViewScope) async throws -> PurchaseCheck {
        if let failure { throw failure }
        checkedAmounts.append(amount)
        checkedScopes.append(scope)
        return check(amount, scope)
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    private static func day(_ day: CalendarDay, plus offset: Int) -> CalendarDay {
        CalendarDay(date: day.startOfDay.addingTimeInterval(TimeInterval(offset * 86_400 + 43_200)))
    }
}
