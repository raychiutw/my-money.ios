import Foundation
import MyMoneyDomain
import Observation

/// 總覽 tab 的 model(parity.md「總覽」)。
@MainActor
@Observable
public final class OverviewModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// 預設全部;選過的視角記在 UserDefaults。
    public var scope: ViewScope {
        didSet { defaults.set(scope.rawValue, forKey: Self.scopeKey) }
    }

    public private(set) var phase: Phase = .loading
    public private(set) var summary: BalanceSummary?
    public private(set) var cashWallets: [CashWallet] = []
    public private(set) var bankAccounts: [BankAccount] = []
    public private(set) var creditCards: [CreditCard] = []

    /// 信用卡詳細頁(點帳戶一覽的信用卡精簡列 push,#73):跟帳戶一覽同一個帳戶檢視範圍。
    public func makeCardDetail(for card: CreditCard) -> CreditCardDetailModel {
        CreditCardDetailModel(
            card: card, bankAccounts: bankAccounts, loadedVersion: loadedVersion, scope: scope.accountScope,
            repository: accountRepository,
            dataVersion: dataVersion, today: today
        )
    }

    public private(set) var recentTransactions: [MyMoneyDomain.Transaction] = []
    public private(set) var monthIncome: Money = .zero
    public private(set) var monthExpense: Money = .zero
    /// 超支警告：每個超支的分類一列(#75),順序跟後端一樣。
    public private(set) var overBudgets: [OverBudget] = []
    public private(set) var topGoals: [SavingsGoal] = []

    /// 後端算好的 30 天現金流預測，給首頁的走勢圖用(#116)。只有視角是「全部」時有值(預測是整體的現金流，
    /// 不分家庭公帳或個人);載入失敗時是 `nil`，不影響總覽的其他區塊。
    public private(set) var forecast: CashFlowForecast?

    /// 走勢圖的呈現資料:零線位置、紅色切換點等。
    public var forecastTrend: ForecastTrend? { forecast.map(ForecastTrend.init(forecast:)) }

    /// 走勢圖的 VoiceOver 摘要，例如「未來 30 天預測餘額，最低餘額 53,440 元，10月5日，不會透支」。
    public var forecastSummary: String? {
        forecastTrend?.spokenSummary(today: today(), locale: locale)
    }

    @ObservationIgnored private let accountRepository: any AccountRepository
    @ObservationIgnored private let transactionRepository: any TransactionRepository
    @ObservationIgnored private let statisticsRepository: any StatisticsRepository
    @ObservationIgnored private let goalRepository: any SavingsGoalRepository
    @ObservationIgnored private let forecastRepository: (any ForecastRepository)?
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let currentUser: UserID?
    @ObservationIgnored private var loadedVersion: Int?
    @ObservationIgnored private var loadedScope: ViewScope?

    private static let scopeKey = "overview.scope"

    /// `currentUser` 是登入的人：最近交易裡自己記的不顯示記帳人。
    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        statistics: any StatisticsRepository,
        goals: any SavingsGoalRepository,
        forecast: (any ForecastRepository)? = nil,
        dataVersion: DataVersion,
        defaults: UserDefaults,
        currentUser: UserID? = nil,
        today: @escaping () -> CalendarDay = { CalendarDay.today() },
        locale: Locale = .autoupdatingCurrent
    ) {
        accountRepository = accounts
        transactionRepository = transactions
        statisticsRepository = statistics
        goalRepository = goals
        forecastRepository = forecast
        self.dataVersion = dataVersion
        self.defaults = defaults
        self.currentUser = currentUser
        self.today = today
        self.locale = locale
        scope = defaults.string(forKey: Self.scopeKey).flatMap(ViewScope.init(rawValue:)) ?? .all
    }

    public var monthNet: Money { monthIncome - monthExpense }

    /// 最近交易的日期，例如「9月28日」(清單格式，不是今年的加上年份，#79)。
    public func dateText(of transaction: MyMoneyDomain.Transaction) -> String {
        transaction.date.text(today: today(), locale: locale)
    }

    /// 最近交易的記帳人：只有不是自己記的才顯示(#72)。
    public func recorderName(of transaction: MyMoneyDomain.Transaction) -> String? {
        transaction.recorderName(besides: currentUser)
    }

    /// 標題隨視角改變;「個人」是我記的全部(parity 刻意偏離第 9 項)。
    public var netTitle: String {
        switch scope {
        case .all: "當月淨收支"
        case .household: "當月淨收支(家庭)"
        case .personal: "當月淨收支(個人)"
        }
    }

    public var overBudgetTitle: String { "有 \(overBudgets.count) 個分類支出已超出預算" }


    /// 載入總覽的所有區塊。當月淨收支用當月的收支趨勢(後端排除「信用卡還款」);預算額度帶入明確的當月。
    public func load() async {
        let version = dataVersion.value
        let scope = scope
        let month = CalendarMonth(today())
        do {
            async let summary = accountRepository.balanceSummary(scope: scope.accountScope)
            async let accounts = accountRepository.accounts(scope: scope.accountScope)
            async let recent = transactionRepository.transactions(from: nil, to: nil, scope: scope, limit: 6, offset: 0)
            async let summaries = statisticsRepository.monthlySummaries(year: month.year, scope: scope)
            async let budgets = statisticsRepository.budgets(month: month)
            async let goals = goalRepository.goals()
            // 預測是額外的資料來源:失敗不能讓整個總覽失敗，所以不 throw，失敗就是沒有走勢圖。
            async let forecast = Self.fetchForecast(forecastRepository, scope: scope)
            let (loadedSummary, loadedAccounts, loadedRecent, loadedSummaries, loadedBudgets, loadedGoals) =
                try await (summary, accounts, recent, summaries, budgets, goals)
            let loadedForecast = await forecast
            // 被取消(換了視角)或已經過期的結果不套用。
            guard !Task.isCancelled, scope == self.scope else { return }
            self.summary = loadedSummary
            cashWallets = loadedAccounts.compactMap { if case .cash(let wallet) = $0 { wallet } else { nil } }
            bankAccounts = loadedAccounts.compactMap { if case .bank(let account) = $0 { account } else { nil } }
            creditCards = loadedAccounts.compactMap { if case .creditCard(let card) = $0 { card } else { nil } }
            recentTransactions = loadedRecent
            let thisMonth = loadedSummaries.first { $0.month == month }
            monthIncome = thisMonth?.income ?? .zero
            monthExpense = thisMonth?.expense ?? .zero
            overBudgets = loadedBudgets.filter(\.isOver).map(OverBudget.init)
            topGoals = Array(loadedGoals.prefix(3))
            self.forecast = loadedForecast
            loadedVersion = version
            loadedScope = scope
            phase = .loaded
        } catch {
            // 被取消的載入不是載入失敗;下一次載入會更新畫面。
            guard !Task.isCancelled, scope == self.scope else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// 只有視角是「全部」才取預測;失敗是 `nil`。
    private static func fetchForecast(_ repository: (any ForecastRepository)?, scope: ViewScope) async -> CashFlowForecast? {
        guard scope == .all, let repository else { return nil }
        return try? await repository.forecast()
    }

    /// 資料版本或視角在上一次載入之後改變過，才重新載入;從信用卡詳細頁返回時不重抓。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value || loadedScope != scope else { return }
        await load()
    }
}

/// 超支警告的一列：分類名稱和超支金額(#75)。已花、預算額度在統計頁的預算額度。
public struct OverBudget: Identifiable, Hashable, Sendable {
    public let category: TransactionCategory
    /// 超支金額：已花減預算額度(web 的 Dashboard 也是這樣算)。
    public let overspent: Money

    public init(category: TransactionCategory, overspent: Money) {
        self.category = category
        self.overspent = overspent
    }

    /// 超支用後端的 `over` 判斷，這裡只算超出多少。
    init(_ budget: Budget) {
        self.init(category: budget.category, overspent: budget.spent - budget.amount)
    }

    public var id: String { category.name }
}

extension ViewScope {
    /// 視角套用到淨可用餘額和帳戶一覽時的帳戶檢視範圍：web 的總覽兩者帶同一個 `scope`,
    /// 所以「個人」視角(我記的全部交易記錄)看的是我的個人私帳帳戶。
    var accountScope: AccountScope {
        switch self {
        case .all: .all
        case .household: .household
        case .personal: .personal
        }
    }
}

extension AccountScope {
    /// 帳戶一覽在這個範圍一個帳戶都沒有時的標題(web 的 Dashboard 依範圍顯示不同的空狀態)。
    public var emptyAccountsTitle: String {
        switch self {
        case .all: "尚未建立帳戶"
        case .household: "目前無家庭公用帳戶"
        case .personal: "目前無個人私帳"
        }
    }

    /// 空狀態的說明，附「前往帳戶管理」。
    public var emptyAccountsHint: String {
        switch self {
        case .household: "至帳戶管理將帳戶屬性設為家庭公用（共同基金或家庭卡）即可在此呈現"
        case .all, .personal: "至帳戶管理新增你的銀行存款帳戶、現金錢包或信用卡"
        }
    }
}
