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
            dataVersion: dataVersion, permissions: permissions, today: today
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
    @ObservationIgnored private let permissions: PermissionsModel?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var loadedVersion: Int?
    @ObservationIgnored private var loadedScope: ViewScope?

    private static let scopeKey = "overview.scope"

    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        statistics: any StatisticsRepository,
        goals: any SavingsGoalRepository,
        forecast: (any ForecastRepository)? = nil,
        dataVersion: DataVersion,
        permissions: PermissionsModel? = nil,
        defaults: UserDefaults,
        today: @escaping () -> CalendarDay = { CalendarDay.today() },
        locale: Locale = .autoupdatingCurrent
    ) {
        accountRepository = accounts
        transactionRepository = transactions
        statisticsRepository = statistics
        goalRepository = goals
        forecastRepository = forecast
        self.dataVersion = dataVersion
        self.permissions = permissions
        self.defaults = defaults
        self.today = today
        self.locale = locale
        scope = defaults.string(forKey: Self.scopeKey).flatMap(ViewScope.init(rawValue:)) ?? .all
    }

    public var monthNet: Money { monthIncome - monthExpense }

    /// 標題隨視角改變;「個人私帳」是我記的全部(parity 刻意偏離第 9 項)。
    public var netTitle: String {
        switch scope {
        case .all: "當月淨收支"
        case .household: "當月淨收支(\(OwnershipName.household))"
        case .personal: "當月淨收支(\(OwnershipName.personal))"
        }
    }

    public var overBudgetTitle: String { "有 \(overBudgets.count) 個分類支出已超出預算" }

    /// 超支提示的畫面文字(#117):精簡的「N 個分類超支」;VoiceOver 念 `overBudgetTitle` 的完整一句。
    public var overBudgetChipTitle: String { "\(overBudgets.count) 個分類超支" }

    /// 信用卡待繳磚(#117):所有信用卡的已出帳待繳款加未出帳款，用後端的合計(跟帳戶頁的信用卡待繳總額同一個算法)。
    public var totalCardDue: Money? { summary.map { $0.billedDebtTotal + $0.unbilledDebtTotal } }

    /// 三格數字磚(#127):畫面標籤用簡稱，VoiceOver 念 `CONTEXT.md` 的正名(視角也只寫在 VoiceOver，畫面上的標籤才不會被截斷)。
    /// 還沒載入時是空的。
    public var summaryTiles: [SummaryTile] {
        guard let summary else { return [] }
        let cardDue = totalCardDue ?? .zero
        return [
            SummaryTile(title: "可支配現金", spokenTitle: "真實可支配現金", amount: summary.disposableCash, isWarning: summary.disposableCash < .zero),
            SummaryTile(title: "當月淨收支", spokenTitle: netTitle, amount: monthNet, isWarning: monthNet < .zero),
            SummaryTile(title: "信用卡待繳", spokenTitle: "信用卡待繳", amount: cardDue, isWarning: cardDue > .zero),
        ]
    }

    /// 帳戶卡片最多幾張;其餘用「管理」到帳戶頁(#117)。
    public static let accountCardLimit = 6

    /// 總覽的帳戶卡片:順序跟帳戶頁一樣(現金錢包、銀行存款帳戶、信用卡)，最多 `accountCardLimit` 張。
    public var accountCards: [OverviewAccountCard] {
        let all = cashWallets.map(OverviewAccountCard.init) + bankAccounts.map(OverviewAccountCard.init)
            + creditCards.map { card in
                // 公帳視角裡的個人卡是「私卡代墊」(上游 ADR 0015);他人的卡脫敏。
                OverviewAccountCard(
                    card, isPrivateCardAdvance: scope.accountScope == .household && !card.isJointFund,
                    isMasked: permissions?.current.isMasked(card) ?? card.isMasked
                )
            }
        return Array(all.prefix(Self.accountCardLimit))
    }

    /// 還有帳戶沒有顯示在卡片上。
    public var hasMoreAccounts: Bool {
        cashWallets.count + bankAccounts.count + creditCards.count > Self.accountCardLimit
    }


    /// 載入總覽的所有區塊。當月淨收支用當月的收支趨勢(後端排除「信用卡還款」);預算額度帶入明確的當月。
    public func load() async {
        let version = dataVersion.value
        let scope = scope
        let month = CalendarMonth(today())
        do {
            async let summary = accountRepository.balanceSummary(scope: scope.accountScope)
            async let accounts = accountRepository.accounts(scope: scope.accountScope)
            async let recent = transactionRepository.transactions(from: nil, to: nil, scope: scope, limit: 5, offset: 0)
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

    /// 用目前視角的預測(上游 ADR 0016:預測依視角分流);失敗是 `nil`，不影響其他區塊。
    private static func fetchForecast(_ repository: (any ForecastRepository)?, scope: ViewScope) async -> CashFlowForecast? {
        guard let repository else { return nil }
        return try? await repository.forecast(scope: scope)
    }

    /// 資料版本或視角在上一次載入之後改變過，才重新載入;從信用卡詳細頁返回時不重抓。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value || loadedScope != scope else { return }
        await load()
    }
}

/// 總覽的一格數字磚(#127)。
public struct SummaryTile: Identifiable, Hashable, Sendable {
    /// 畫面上的簡稱。
    public let title: String
    /// VoiceOver 念的正名。
    public let spokenTitle: String
    public let amount: Money
    /// 用警示色(負數的可支配現金與淨收支、有待繳的信用卡)。
    public let isWarning: Bool

    public var id: String { title }
}

/// 總覽帳戶卡片的一張(#117):名稱加大金額。信用卡的金額是信用卡待繳總額，有待繳時用警示色，另外有「N 日繳」。
public struct OverviewAccountCard: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case cash
        case bank
        case creditCard(CreditCard)
    }

    public let id: AccountID
    public let name: String
    public let colorHex: String
    public let amount: Money
    public let kind: Kind
    /// 公帳視角裡的個人信用卡(私卡代墊，上游 ADR 0015)，以及它是不是脫敏的他人私卡:VoiceOver 念法不同。
    private let isPrivateCardAdvance: Bool
    private let isMasked: Bool

    init(_ wallet: CashWallet) {
        (id, name, colorHex, amount, kind) = (wallet.id, wallet.name, wallet.colorHex, wallet.balance, .cash)
        (isPrivateCardAdvance, isMasked) = (false, false)
    }

    init(_ account: BankAccount) {
        (id, name, colorHex, amount, kind) = (account.id, account.name, account.colorHex, account.balance, .bank)
        (isPrivateCardAdvance, isMasked) = (false, false)
    }

    init(_ card: CreditCard, isPrivateCardAdvance: Bool = false, isMasked: Bool = false) {
        (id, name, colorHex, amount, kind) = (card.id, card.name, card.colorHex, card.totalDue, .creditCard(card))
        (self.isPrivateCardAdvance, self.isMasked) = (isPrivateCardAdvance, isMasked)
    }

    /// 卡片上的類型圖示(用帳戶的代表色)。
    public var symbolName: String {
        switch kind {
        case .cash: "wallet.bifold"
        case .bank: "building.columns"
        case .creditCard: "creditcard"
        }
    }

    public var isCreditCard: Bool {
        if case .creditCard = kind { true } else { false }
    }

    /// 信用卡有待繳款:金額用警示色。
    public var isDue: Bool { isCreditCard && amount > .zero }

    /// 視覺上的繳款日,例如「5 日繳」;沒有設定繳款日(或不是信用卡)時是 `nil`。
    public var dueDayText: String? {
        guard case .creditCard(let card) = kind, let day = card.paymentDueDay else { return nil }
        return "\(day) 日繳"
    }

    /// 現金錢包、銀行存款帳戶:「名稱，類型，餘額 X 元」;信用卡:「名稱，信用卡待繳總額 X 元，每月 N 日繳款」。
    public var spokenText: String {
        switch kind {
        case .cash: "\(name)，\(Terms.cash)，餘額 \(amount.spokenText)"
        case .bank: "\(name)，\(Terms.bankAccount)，餘額 \(amount.spokenText)"
        case .creditCard(let card):
            if isPrivateCardAdvance {
                card.spokenAdvanceSummary(isMasked: isMasked)
            } else {
                ["\(name)", "信用卡待繳總額 \(amount.spokenText)", card.paymentDueDay.map { "每月 \($0) 日繳款" }]
                    .compactMap { $0 }.joined(separator: "，")
            }
        }
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
        case .household: "目前無\(OwnershipName.household)帳戶"
        case .personal: "目前無\(OwnershipName.personal)帳戶"
        }
    }

    /// 空狀態的說明，附「前往帳戶管理」。
    public var emptyAccountsHint: String {
        switch self {
        case .household: "至帳戶管理將帳戶歸屬設為\(OwnershipName.household)即可在此呈現"
        case .all, .personal: "至帳戶管理新增你的\(Terms.bankAccount)、\(Terms.cash)或信用卡"
        }
    }
}
