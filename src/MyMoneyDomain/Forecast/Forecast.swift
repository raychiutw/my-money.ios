/// 現金流預測的一天：當天結束時的餘額。
public struct DailyBalance: Hashable, Sendable {
    public let date: CalendarDay
    public let balance: Money

    public init(date: CalendarDay, balance: Money) {
        self.date = date
        self.balance = balance
    }
}

/// 預定收支：未來 30 天內，週期收支或信用卡繳款日(「繳卡費」,上游 ADR 0017)預計發生的一次。
public struct ForecastEvent: Hashable, Sendable {
    public let date: CalendarDay
    public let name: String
    public let type: TransactionType
    public let amount: Money
    /// 歸屬(後端 `is_shared`):家庭公帳是 `true`;舊回應沒有時是個人私帳。
    public let isShared: Bool
    /// 資產帳戶名稱(後端 `account_name`):週期項目綁的帳戶，或「繳卡費」那張卡;沒有就是 `nil`。
    public let accountName: String?
    /// 這一次排程的唯一識別碼(後端 `event_key`，上游 ADR 0018):`recurring:<id>:<日期>` 或 `card_due:<帳戶>:<日期>`;舊回應沒有。
    public let key: String?
    /// 已標示為「已繳」:後端已把它從逐日餘額、最低餘額與購買力試算排除。
    public let isSettled: Bool
    /// 目前登入者能不能勾選(後端 `can_settle`):私帳事件只有本人，公帳事件是本人或家庭管理員;舊回應沒有，當成不能。
    public let canSettle: Bool

    public init(
        date: CalendarDay, name: String, type: TransactionType, amount: Money, isShared: Bool = false, accountName: String? = nil,
        key: String? = nil, isSettled: Bool = false, canSettle: Bool = false
    ) {
        self.date = date
        self.name = name
        self.type = type
        self.amount = amount
        self.isShared = isShared
        self.accountName = accountName
        self.key = key
        self.isSettled = isSettled
        self.canSettle = canSettle
    }
}

/// 現金流預測(後端算好的 `GET /forecast`):只算自己的資產帳戶與週期收支。
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
    /// 審慎評估：不會透支，但扣掉這筆後的淨可用餘額低於每月預留合計。
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
    /// 這個視角的 30 天預測(上游 ADR 0016):起始餘額、預定收支都由後端依視角算好。
    func forecast(scope: ViewScope) async throws -> CashFlowForecast

    /// 這個視角的購買力試算;公帳視角後端不檢核成員個人的儲蓄目標。
    func checkPurchase(_ amount: Money, scope: ViewScope) async throws -> PurchaseCheck

    /// 標示或取消一筆預測事件的「已繳」(上游 ADR 0018):只豁免這一次排程，下個週期不受影響。
    func setSettled(_ settled: Bool, forEventKey key: String) async throws
}
