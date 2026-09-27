/// 現金流預測的一天：當天結束時的餘額。
public struct DailyBalance: Hashable, Sendable {
    public let date: CalendarDay
    public let balance: Money

    public init(date: CalendarDay, balance: Money) {
        self.date = date
        self.balance = balance
    }
}

/// 預定收支：未來 30 天內，固定收支預計發生的一次。
public struct ForecastEvent: Hashable, Sendable {
    public let date: CalendarDay
    public let name: String
    public let type: TransactionType
    public let amount: Money

    public init(date: CalendarDay, name: String, type: TransactionType, amount: Money) {
        self.date = date
        self.name = name
        self.type = type
        self.amount = amount
    }
}

/// 現金流預測(後端算好的 `GET /forecast`):只算自己的資金帳戶與固定收支。
public struct CashFlowForecast: Hashable, Sendable {
    public let dailyBalances: [DailyBalance]
    public let minBalance: Money
    /// 最低餘額發生的日期;餘額一直沒有低於起始餘額時是 `nil`。
    public let minDate: CalendarDay?
    /// 透支風險：最低餘額低於 0。
    public let willOverdraft: Bool
    public let events: [ForecastEvent]

    public init(dailyBalances: [DailyBalance], minBalance: Money, minDate: CalendarDay?, willOverdraft: Bool, events: [ForecastEvent]) {
        self.dailyBalances = dailyBalances
        self.minBalance = minBalance
        self.minDate = minDate
        self.willOverdraft = willOverdraft
        self.events = events
    }
}

/// 購買力試算的評估結果(後端依序判定)。raw value 是後端的 `verdict`。
public enum PurchaseVerdict: String, Hashable, Sendable {
    /// 放心購買。
    case safe
    /// 審慎評估：不會透支，但扣掉這筆後的淨可用資產低於每月預留合計。
    case caution
    /// 不建議購買：扣掉這筆後會有透支風險。
    case danger
}

/// 購買力試算的結果。
public struct PurchaseCheck: Hashable, Sendable {
    public let amount: Money
    public let verdict: PurchaseVerdict
    public let minBalance: Money
    /// 有每月預留的儲蓄目標名稱。
    public let affectedGoalNames: [String]

    public init(amount: Money, verdict: PurchaseVerdict, minBalance: Money, affectedGoalNames: [String]) {
        self.amount = amount
        self.verdict = verdict
        self.minBalance = minBalance
        self.affectedGoalNames = affectedGoalNames
    }
}

/// 現金流預測(`/forecast`)。
public protocol ForecastRepository: Sendable {
    func forecast() async throws -> CashFlowForecast

    func checkPurchase(_ amount: Money) async throws -> PurchaseCheck
}
