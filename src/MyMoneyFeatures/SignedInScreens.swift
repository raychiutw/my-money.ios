import MyMoneyDomain
import Observation

/// 登入後各個 tab 的畫面 model。由 composition root 建立。
@MainActor
public struct MainScreens {
    public let accounts: AccountsModel
    public let transactions: TransactionsModel

    /// 「記一筆」:每個 session 一份，讓下一筆沿用上一筆的選擇。
    public let quickEntry: QuickEntryModel

    /// 規劃 → 固定收支。
    public let recurring: RecurringModel

    /// 規劃 → 儲蓄目標。
    public let goals: SavingsGoalsModel

    public let statistics: StatisticsModel

    /// 用同一份資料版本組出這個 session 的所有畫面 model。
    public init(
        accountRepository: any AccountRepository,
        transactionRepository: any TransactionRepository,
        recurringRepository: any RecurringRepository,
        savingsGoalRepository: any SavingsGoalRepository,
        statisticsRepository: any StatisticsRepository
    ) {
        let dataVersion = DataVersion()
        accounts = AccountsModel(repository: accountRepository, dataVersion: dataVersion)
        transactions = TransactionsModel(repository: transactionRepository, accounts: accountRepository, dataVersion: dataVersion)
        quickEntry = QuickEntryModel(transactions: transactionRepository, accounts: accountRepository, dataVersion: dataVersion)
        recurring = RecurringModel(repository: recurringRepository, accounts: accountRepository, dataVersion: dataVersion)
        goals = SavingsGoalsModel(repository: savingsGoalRepository, dataVersion: dataVersion)
        statistics = StatisticsModel(repository: statisticsRepository, dataVersion: dataVersion)
    }
}

/// 讓登入後的畫面 model 跟著 session 建立：換了一個人就重建，登出就丟掉。
@MainActor
@Observable
public final class SignedInScreens {
    public private(set) var current: MainScreens?

    @ObservationIgnored private let make: @MainActor () -> MainScreens
    @ObservationIgnored private var userID: UserID?

    public init(make: @escaping @MainActor () -> MainScreens) {
        self.make = make
    }

    /// 同一個人時沿用現有的畫面;換人或登出時重建或丟掉，避免在共用的裝置上看到上一個人的資料。
    public func update(for session: Session?) {
        guard session?.user.id != userID else { return }
        userID = session?.user.id
        current = session == nil ? nil : make()
    }
}
