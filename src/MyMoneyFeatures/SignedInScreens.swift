import Foundation
import MyMoneyDomain
import Observation

/// 登入後各個 tab 的畫面 model。由 composition root 建立。
@MainActor
public struct MainScreens {
    public let overview: OverviewModel
    public let accounts: AccountsModel
    public let transactions: TransactionsModel

    /// 「記一筆」:每個 session 一份，讓下一筆沿用上一筆的選擇。
    public let quickEntry: QuickEntryModel

    /// 規劃 → 週期收支。
    public let recurring: RecurringModel

    /// 規劃 → 儲蓄目標。
    public let goals: SavingsGoalsModel

    public let statistics: StatisticsModel

    /// 規劃 → 現金流預測。
    public let forecast: ForecastModel

    /// 家庭 tab。
    public let household: HouseholdModel

    /// 「我的」 → 機器人記帳。
    public let bot: BotModel

    /// 用同一份資料版本組出這個 session 的所有畫面 model。
    /// `currentUser` 是登入的人(交易頁自己記的交易記錄不顯示記帳人);`defaults` 存總覽選過的視角。
    public init(
        currentUser: UserID,
        accountRepository: any AccountRepository,
        transactionRepository: any TransactionRepository,
        recurringRepository: any RecurringRepository,
        savingsGoalRepository: any SavingsGoalRepository,
        statisticsRepository: any StatisticsRepository,
        forecastRepository: any ForecastRepository,
        householdRepository: any HouseholdRepository,
        botRepository: any BotRepository,
        defaults: UserDefaults = .standard
    ) {
        let dataVersion = DataVersion()
        // 編輯權限(上游 ADR 0013、#133):角色在登入時問一次，帳戶頁、交易頁、信用卡詳細頁共用;家庭頁載入後同步。
        let permissions = PermissionsModel(userID: currentUser, households: householdRepository)
        Task { await permissions.loadIfNeeded() }
        overview = OverviewModel(
            accounts: accountRepository, transactions: transactionRepository, statistics: statisticsRepository,
            goals: savingsGoalRepository, forecast: forecastRepository, dataVersion: dataVersion, permissions: permissions,
            defaults: defaults
        )
        accounts = AccountsModel(repository: accountRepository, dataVersion: dataVersion, permissions: permissions)
        transactions = TransactionsModel(
            repository: transactionRepository, accounts: accountRepository, dataVersion: dataVersion, currentUser: currentUser,
            permissions: permissions
        )
        quickEntry = QuickEntryModel(transactions: transactionRepository, accounts: accountRepository, dataVersion: dataVersion)
        recurring = RecurringModel(repository: recurringRepository, accounts: accountRepository, dataVersion: dataVersion)
        goals = SavingsGoalsModel(repository: savingsGoalRepository, dataVersion: dataVersion)
        statistics = StatisticsModel(repository: statisticsRepository, dataVersion: dataVersion)
        forecast = ForecastModel(repository: forecastRepository, dataVersion: dataVersion)
        household = HouseholdModel(
            repository: householdRepository, accounts: accountRepository, statistics: statisticsRepository,
            currentUser: currentUser, permissions: permissions, dataVersion: dataVersion
        )
        bot = BotModel(repository: botRepository, dataVersion: dataVersion)
    }
}

/// 讓登入後的畫面 model 跟著 session 建立：換了一個人就重建，登出就丟掉。
@MainActor
@Observable
public final class SignedInScreens {
    public private(set) var current: MainScreens?

    @ObservationIgnored private let make: @MainActor (User) -> MainScreens
    @ObservationIgnored private var userID: UserID?

    /// `make` 替登入的人建立一份畫面;每次換人登入時重建，不沿用上一個人的狀態。
    public init(make: @escaping @MainActor (User) -> MainScreens) {
        self.make = make
    }

    /// 同一個人時沿用現有的畫面;換人或登出時重建或丟掉，避免在共用的裝置上看到上一個人的資料。
    public func update(for session: Session?) {
        guard session?.user.id != userID else { return }
        userID = session?.user.id
        current = session.map { make($0.user) }
    }
}
