import Foundation
import MyMoneyDomain
import Observation

/// 週期收支頁的 model(parity.md「週期收支」)。
@MainActor
@Observable
public final class RecurringModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    public private(set) var items: [RecurringItem] = []
    private var amortization: RecurringAmortization = .zero

    /// 視角(上游 ADR 0016):預設全部;選過的視角記在 UserDefaults，下次沿用。
    public var scope: ViewScope {
        didSet { defaults.set(scope.rawValue, forKey: Self.scopeKey) }
    }

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    @ObservationIgnored private let repository: any RecurringRepository
    @ObservationIgnored private let accountRepository: any AccountRepository
    @ObservationIgnored public let dataVersion: DataVersion
    /// 編輯權限(登入的人與家庭角色);沒有時所有項目都當作能改，交給後端的 403 把關。
    @ObservationIgnored private let permissions: PermissionsModel?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private var loadedVersion: Int?
    @ObservationIgnored private var loadedScope: ViewScope?

    private static let scopeKey = "recurring.scope"

    public init(
        repository: any RecurringRepository,
        accounts: any AccountRepository,
        dataVersion: DataVersion,
        permissions: PermissionsModel? = nil,
        defaults: UserDefaults = .standard,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        accountRepository = accounts
        self.dataVersion = dataVersion
        self.permissions = permissions
        self.defaults = defaults
        self.today = today
        scope = defaults.string(forKey: Self.scopeKey).flatMap(ViewScope.init(rawValue:)) ?? .all
    }

    public var expenses: [RecurringItem] { items.filter { $0.type == .expense } }
    public var incomes: [RecurringItem] { items.filter { $0.type == .income } }

    /// 週期支出的分攤平滑合計(後端算好)。
    public var monthlyExpense: Money { amortization.monthlyExpense }
    /// 週期收入的分攤平滑合計(後端算好)。
    public var monthlyIncome: Money { amortization.monthlyIncome }
    /// 每月週期淨額：週期收入減週期支出。
    public var monthlyNet: Money { monthlyIncome - monthlyExpense }

    /// 載入週期收支與分攤平滑。任一個失敗都顯示載入失敗，不把分攤平滑當成 0
    /// (web 用 `.catch(() => null)` 顯示 $0,parity 刻意偏離第 27 項)。重新載入時保留舊資料。
    public func load() async {
        let version = dataVersion.value
        let scope = scope
        do {
            async let items = repository.items(scope: scope)
            async let amortization = repository.amortization(scope: scope)
            let (loadedItems, loadedAmortization) = try await (items, amortization)
            // 被取消(換了視角)或已經過期的結果不套用。
            guard !Task.isCancelled, scope == self.scope else { return }
            self.items = loadedItems
            self.amortization = loadedAmortization
            loadedVersion = version
            loadedScope = scope
            phase = .loaded
        } catch {
            // 被取消的載入不是載入失敗;下一次載入會更新畫面。
            guard !Task.isCancelled, scope == self.scope else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// 資料版本或視角在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value || loadedScope != scope else { return }
        await load()
    }

    // MARK: 編輯權限(上游 ADR 0016)

    /// 這一項我能不能改:個人私帳只有建立者本人;家庭公帳是建立者本人或家庭管理員。
    public func canModify(_ item: RecurringItem) -> Bool {
        permissions?.current.canModify(item) ?? true
    }

    /// 說明 alert 的標題。
    public let lockAlertTitle = "不能編輯這個週期收支"

    /// 點不開的項目為什麼不能編輯(點一下跳出的說明);可以改的是 `nil`。
    public func lockReason(for item: RecurringItem) -> String? {
        if canModify(item) { return nil }
        return item.isShared
            ? "他人建立的\(OwnershipName.household)，僅建立者或家庭管理員可以編輯、刪除"
            : "他人的\(OwnershipName.personal)，僅建立者本人可以編輯、刪除"
    }

    /// 點不開的項目的 VoiceOver 提示;可以改的是 `nil`。
    public func lockHint(for item: RecurringItem) -> String? {
        lockReason(for: item) == nil ? nil : "點兩下查看為什麼不能編輯"
    }

    public func deleteConfirmation(for item: RecurringItem) -> String {
        "確定要刪除週期收支「\(item.name)」嗎？"
    }

    /// 刪除;成功後遞增資料版本。
    public func delete(_ item: RecurringItem) async {
        do {
            try await repository.delete(item.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    public func makeEditor() -> RecurringEditorModel {
        RecurringEditorModel(adding: (), repository: repository, accounts: accountRepository, dataVersion: dataVersion)
    }

    public func makeEditor(editing item: RecurringItem) -> RecurringEditorModel {
        RecurringEditorModel(editing: item, repository: repository, accounts: accountRepository, dataVersion: dataVersion)
    }

    /// 週期收支的 CSV,檔名跟 web 一樣是 `recurring-今天.csv`。
    public func csvExport() -> CSVExport {
        let repository = repository
        return CSVExport(fileName: "recurring-\(today().iso).csv") {
            try await repository.exportCSV()
        }
    }
}

extension RecurringItem {
    /// 確切時程，照上游 web 的 `formatScheduleLabel`(`feabed3`，#131):「每月 5 號扣款」「單數月 10 號扣款」
    /// 「每季 (1/4/7/10月) 5 號扣款」「每半年 (1/7月) 1 號入帳」「每年 5 月 15 號扣款」;收入寫「入帳」、支出寫「扣款」。
    public var scheduleText: String {
        let action = type == .expense ? "扣款" : "入帳"
        let month = cycle.clampedMonth(monthOfCycle)
        switch cycle {
        case .monthly: return "每月 \(dayOfCycle) 號\(action)"
        case .bimonthly: return "\(month == 1 ? "單數月" : "雙數月") \(dayOfCycle) 號\(action)"
        case .quarterly: return "每季 (\(cycle.monthList(from: month, separator: "/"))月) \(dayOfCycle) 號\(action)"
        case .semiannual: return "每半年 (\(cycle.monthList(from: month, separator: "/"))月) \(dayOfCycle) 號\(action)"
        case .annual: return "每年 \(month) 月 \(dayOfCycle) 號\(action)"
        }
    }

    /// 週期不是每月的週期支出才顯示分攤平滑;週期收入不顯示。
    public var showsMonthlyAmortization: Bool {
        type == .expense && cycle != .monthly
    }

    /// 列的「建立者・歸屬」,例如「小美・家庭公帳」;自己建立的也顯示。不知道建立者時只有歸屬。
    public var ownerText: String {
        [ownerName, OwnershipName.title(isShared: isShared)].compactMap { $0 }.joined(separator: "・")
    }

    /// 列的資產帳戶名稱，不加「關聯扣款帳戶：」前綴;沒設就不顯示(DESIGN.md「列與欄位」,#77)。
    public var accountText: String? { accountName }

    /// 金額下方的每月分攤平滑，例如「$2,000／月」;只有週期不是每月的週期支出才有。
    public var amortizationText: String? {
        showsMonthlyAmortization ? "\(monthlyAmortization.formatted())／月" : nil
    }

    /// VoiceOver 把整列念成一句，例如「年繳保費，週期支出 24,000 元，每年 1 月 15 號扣款，分攤平滑每月 2,000 元」。
    public var spokenText: String {
        var parts = [name, "\(type == .income ? "週期收入" : "週期支出") \(amount.spokenText)", scheduleText]
        if let ownerName { parts.append("建立者 \(ownerName)") }
        parts.append(OwnershipName.title(isShared: isShared))
        if let accountText { parts.append("帳戶 \(accountText)") }
        if showsMonthlyAmortization { parts.append("分攤平滑每月 \(monthlyAmortization.spokenText)") }
        return parts.joined(separator: "，")
    }
}

extension RecurringCycle {
    /// 跟 web 的 `CYCLE_LABELS` 一樣。
    public var label: String {
        switch self {
        case .monthly: "每月"
        case .bimonthly: "每雙月"
        case .quarterly: "每季"
        case .semiannual: "每半年"
        case .annual: "每年"
        }
    }

    /// 從 `start` 月起每隔一期的月份，例如季繳從 2 月起是「2/5/8/11」。
    func monthList(from start: Int, separator: String) -> String {
        stride(from: start, through: 12, by: months).map(String.init).joined(separator: separator)
    }

    /// 週期選單的文字，例如「每季(3 個月)」。
    public var pickerLabel: String {
        self == .monthly ? label : "\(label)(\(months) 個月)"
    }
}
