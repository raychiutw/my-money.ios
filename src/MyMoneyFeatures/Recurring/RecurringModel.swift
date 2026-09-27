import Foundation
import MyMoneyDomain
import Observation

/// 固定收支頁的 model(parity.md「固定收支」)。
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

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    @ObservationIgnored private let repository: any RecurringRepository
    @ObservationIgnored private let accountRepository: any AccountRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private var loadedVersion: Int?

    public init(
        repository: any RecurringRepository,
        accounts: any AccountRepository,
        dataVersion: DataVersion,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        accountRepository = accounts
        self.dataVersion = dataVersion
        self.today = today
    }

    public var expenses: [RecurringItem] { items.filter { $0.type == .expense } }
    public var incomes: [RecurringItem] { items.filter { $0.type == .income } }

    /// 固定支出的週期攤提合計(後端算好)。
    public var monthlyExpense: Money { amortization.monthlyExpense }
    /// 固定收入的週期攤提合計(後端算好)。
    public var monthlyIncome: Money { amortization.monthlyIncome }
    /// 每月固定淨額：固定收入減固定支出。
    public var monthlyNet: Money { monthlyIncome - monthlyExpense }

    /// 載入固定收支與週期攤提。週期攤提失敗時當作 0(跟 web 一樣)。重新載入時保留舊資料。
    public func load() async {
        let version = dataVersion.value
        do {
            async let items = repository.items()
            async let amortization = try? repository.amortization()
            let (loadedItems, loadedAmortization) = try await (items, amortization)
            self.items = loadedItems
            self.amortization = loadedAmortization ?? .zero
            loadedVersion = version
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 資料版本在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value else { return }
        await load()
    }

    public func deleteConfirmation(for item: RecurringItem) -> String {
        "確定要刪除固定收支「\(item.name)」嗎？"
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

    /// 固定收支的 CSV,檔名跟 web 一樣是 `recurring-今天.csv`。
    public func csvExport() -> CSVExport {
        let repository = repository
        return CSVExport(fileName: "recurring-\(today().iso).csv") {
            try await repository.exportCSV()
        }
    }
}

extension RecurringItem {
    /// 例如「每季 5 號扣款」「每月 25 號入帳」(parity 刻意偏離第 11 項)。
    public var scheduleText: String {
        "\(cycle.label) \(dayOfCycle) 號\(type == .expense ? "扣款" : "入帳")"
    }

    /// 週期不是每月的固定支出才顯示週期攤提;固定收入不顯示。
    public var showsMonthlyAmortization: Bool {
        type == .expense && cycle != .monthly
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

    /// 週期選單的文字，例如「每季(3 個月)」。
    public var pickerLabel: String {
        self == .monthly ? label : "\(label)(\(months) 個月)"
    }
}
