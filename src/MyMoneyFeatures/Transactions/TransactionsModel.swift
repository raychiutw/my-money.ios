import Foundation
import MyMoneyDomain
import Observation

/// 交易頁的一天：當天的交易記錄，以及當日的收入與支出(不含信用卡還款)。
public struct TransactionDay: Identifiable, Sendable {
    public let date: CalendarDay
    public let transactions: [Transaction]
    public let income: Money
    public let expense: Money

    public var id: CalendarDay { date }
}

/// 交易頁的 model(parity.md「交易」)。
///
/// 起迄日與視角送到後端查詢;類型、分類、關鍵字只在本機過濾(跟 web 一樣)。
@MainActor
@Observable
public final class TransactionsModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// 類型篩選(只在本機過濾)。
    public enum TypeFilter: Hashable, Sendable {
        case all
        case expense
        case income
    }

    /// 起日，預設本月 1 號(台灣時間)。
    public var from: CalendarDay
    /// 迄日，預設今天(台灣時間)。
    public var to: CalendarDay
    public var scope: ViewScope = .all

    /// 換類型時，不屬於新類型的分類篩選會清掉。
    public var typeFilter: TypeFilter = .all {
        didSet {
            if let categoryFilter, !categoryOptions.contains(categoryFilter) {
                self.categoryFilter = nil
            }
        }
    }

    /// 分類篩選;`nil` 是全部分類。
    public var categoryFilter: TransactionCategory?

    /// 關鍵字：不分大小寫，比對備註、分類、帳戶名稱與記帳人。
    public var keyword = ""

    public private(set) var phase: Phase = .loading

    /// 刪除失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    public let deleteConfirmation = "確定要刪除這筆交易記錄嗎？"

    /// 從後端載入的區間內所有交易記錄(篩選前)。
    private var loaded: [Transaction] = []

    @ObservationIgnored private let repository: any TransactionRepository
    @ObservationIgnored private let accountRepository: (any AccountRepository)?
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
    @ObservationIgnored private var loadedVersion: Int?

    public init(
        repository: any TransactionRepository,
        accounts: (any AccountRepository)? = nil,
        dataVersion: DataVersion,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        accountRepository = accounts
        self.dataVersion = dataVersion
        self.today = today
        let now = today()
        from = now.firstOfMonth
        to = now
    }

    /// 分類選項隨類型改變;全部類型時是支出加收入，「其他」只出現一次。
    public var categoryOptions: [TransactionCategory] {
        switch typeFilter {
        case .expense:
            TransactionCategory.expenseCategories
        case .income:
            TransactionCategory.incomeCategories
        case .all:
            TransactionCategory.expenseCategories
                + TransactionCategory.incomeCategories.filter { !TransactionCategory.expenseCategories.contains($0) }
        }
    }

    /// 篩選後的交易記錄，依日期分組，新的在前。
    public var days: [TransactionDay] {
        var order: [CalendarDay] = []
        var byDay: [CalendarDay: [Transaction]] = [:]
        for transaction in filtered {
            if byDay[transaction.date] == nil { order.append(transaction.date) }
            byDay[transaction.date, default: []].append(transaction)
        }
        return order.sorted(by: >).map { date in
            let items = byDay[date] ?? []
            return TransactionDay(date: date, transactions: items, income: Self.income(of: items), expense: Self.expense(of: items))
        }
    }

    public var count: Int { filtered.count }
    public var totalIncome: Money { Self.income(of: filtered) }
    /// 總支出不含「信用卡還款」(parity 刻意偏離第 26 項)。
    public var totalExpense: Money { Self.expense(of: filtered) }
    public var net: Money { totalIncome - totalExpense }

    private var filtered: [Transaction] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return loaded.filter { transaction in
            switch typeFilter {
            case .all: break
            case .expense: if transaction.type != .expense { return false }
            case .income: if transaction.type != .income { return false }
            }
            if let categoryFilter, transaction.category != categoryFilter { return false }
            guard !needle.isEmpty else { return true }
            return [transaction.note, transaction.category.name, transaction.accountName ?? "", transaction.recorderName ?? ""]
                .contains { $0.lowercased().contains(needle) }
        }
    }

    /// 依目前的起迄日與視角，抓齊區間內的所有交易記錄。
    public func load() async {
        let version = dataVersion.value
        do {
            loaded = try await repository.allTransactions(from: from, to: to, scope: scope)
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

    /// 4 種系統分類(信用卡還款、內部轉帳、ATM提款、公帳代墊報銷)是系統內部平帳或轉帳的紀錄，不能編輯也不能刪除(後端也會拒絕)。
    public func canModify(_ transaction: Transaction) -> Bool {
        !transaction.isSystemRecord
    }

    public func makeEditor(for transaction: Transaction) -> TransactionEditorModel? {
        guard canModify(transaction), let accountRepository else { return nil }
        return TransactionEditorModel(
            editing: transaction, transactions: repository, accounts: accountRepository, dataVersion: dataVersion
        )
    }

    /// 刪除;成功後遞增資料版本。家人記的也能刪除。
    public func delete(_ transaction: Transaction) async {
        guard canModify(transaction) else { return }
        do {
            try await repository.delete(transaction.id)
            dataVersion.bump()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    /// 目前起迄日的 CSV,檔名跟 web 一樣是 `my-money-今天.csv`。
    public func csvExport() -> CSVExport {
        let repository = repository
        let (from, to) = (from, to)
        return CSVExport(fileName: "my-money-\(today().iso).csv") {
            try await repository.exportCSV(from: from, to: to)
        }
    }

    /// 收入合計，不含系統分類(ATM 提款、轉帳、報銷的收入那一筆也只是資金調度)。
    private static func income(of transactions: [Transaction]) -> Money {
        transactions.filter { $0.type == .income && !$0.isSystemRecord }.reduce(.zero) { $0 + $1.amount }
    }

    /// 支出合計，不含系統分類：信用卡扣款還款、轉帳、ATM 提款、報銷只是資金調度，算進來會跟刷卡或原本的消費重複。
    private static func expense(of transactions: [Transaction]) -> Money {
        transactions.filter { $0.type == .expense && !$0.isSystemRecord }.reduce(.zero) { $0 + $1.amount }
    }
}
