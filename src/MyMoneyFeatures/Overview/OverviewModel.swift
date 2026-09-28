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

    /// 帳戶一覽裡信用卡的兩行說明(web 的 Dashboard):代墊／私帳拆解(沒有待繳時是「卡費已全數結清」),
    /// 以及未出帳與繳款日。
    public static func cardDetailLines(_ card: CreditCard) -> [String] {
        let debt = card.totalDue > .zero
            ? "代墊 \(card.sharedDebt.formatted()) · 私帳 \(card.personalDebt.formatted())"
            : "卡費已全數結清"
        let unbilled = "未出帳 \(card.unbilledDebt.formatted())"
        return [debt, card.paymentDueDay.map { "\(unbilled) · 每月 \($0) 日繳款" } ?? unbilled]
    }

    /// 淨可用資產的組成(web 的 Dashboard 寫成「現金 + 活存 - 卡債」,iOS 用 CONTEXT 的詞):現金 + 銀行存款 - 待繳卡費(已出帳加未出帳)。數字都是後端算好的。
    public var availableBreakdown: String? {
        summary.map {
            "現金 \($0.cashTotal.formatted()) + 銀行存款 \($0.bankBalanceTotal.formatted()) - 待繳卡費 \(($0.billedDebtTotal + $0.unbilledDebtTotal).formatted())"
        }
    }

    public private(set) var recentTransactions: [MyMoneyDomain.Transaction] = []
    public private(set) var monthIncome: Money = .zero
    public private(set) var monthExpense: Money = .zero
    public private(set) var overBudgets: [Budget] = []
    public private(set) var topGoals: [SavingsGoal] = []

    @ObservationIgnored private let accountRepository: any AccountRepository
    @ObservationIgnored private let transactionRepository: any TransactionRepository
    @ObservationIgnored private let statisticsRepository: any StatisticsRepository
    @ObservationIgnored private let goalRepository: any SavingsGoalRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private var loadedVersion: Int?

    private static let scopeKey = "overview.scope"

    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        statistics: any StatisticsRepository,
        goals: any SavingsGoalRepository,
        dataVersion: DataVersion,
        defaults: UserDefaults,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        accountRepository = accounts
        transactionRepository = transactions
        statisticsRepository = statistics
        goalRepository = goals
        self.dataVersion = dataVersion
        self.defaults = defaults
        self.today = today
        scope = defaults.string(forKey: Self.scopeKey).flatMap(ViewScope.init(rawValue:)) ?? .all
    }

    public var monthNet: Money { monthIncome - monthExpense }

    /// 標題隨視角改變;「個人」是我記的全部(parity 刻意偏離第 9 項)。
    public var netTitle: String {
        switch scope {
        case .all: "當月淨收支"
        case .household: "當月淨收支(家庭)"
        case .personal: "當月淨收支(個人)"
        }
    }

    public var overBudgetTitle: String { "有 \(overBudgets.count) 個分類支出已超出預算" }

    /// 家庭財務錦囊。
    public var tipText: String {
        let amortization = summary?.monthlyAmortization ?? .zero
        let reserve = summary?.monthlySavingsReserve ?? .zero
        return "固定支出的週期攤提每月 \(amortization.formatted()),已經從真實可支配現金扣除;"
            + "儲蓄目標的每月預留合計 \(reserve.formatted()),建議每月先存起來。"
            + "家庭公帳全家都看得到，個人私帳只有自己看得到。"
    }

    /// 依裝置的當地時間問候(parity 刻意偏離第 21 項):5 點到中午前是早安，中午到 18 點前是午安，其餘是晚安。
    public nonisolated static func greeting(hour: Int, name: String) -> String {
        let greeting = switch hour {
        case 5..<12: "早安"
        case 12..<18: "午安"
        default: "晚安"
        }
        return "\(greeting)，\(name)"
    }

    /// 載入總覽的所有區塊。當月淨收支用當月的收支趨勢(後端排除「信用卡還款」);分類預算帶入明確的當月。
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
            let (loadedSummary, loadedAccounts, loadedRecent, loadedSummaries, loadedBudgets, loadedGoals) =
                try await (summary, accounts, recent, summaries, budgets, goals)
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
            overBudgets = loadedBudgets.filter(\.isOver)
            topGoals = Array(loadedGoals.prefix(3))
            loadedVersion = version
            phase = .loaded
        } catch {
            // 被取消的載入不是載入失敗;下一次載入會更新畫面。
            guard !Task.isCancelled, scope == self.scope else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// 資料版本在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value else { return }
        await load()
    }
}

extension ViewScope {
    /// 視角套用到淨可用資產和帳戶一覽時的帳戶檢視範圍：web 的總覽兩者帶同一個 `scope`,
    /// 所以「個人」視角(我記的全部交易紀錄)看的是我的個人私帳帳戶。
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
        case .household: "至帳戶管理將帳戶屬性設為「家庭公用」即可在此呈現"
        case .all, .personal: "至帳戶管理新增你的銀行存款帳戶、現金錢包或信用卡"
        }
    }
}
