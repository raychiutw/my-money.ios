import Foundation
import MyMoneyDomain
import Observation

/// 交易頁的一天：當天的交易紀錄，以及當日的收入與支出(不含信用卡還款)。
public struct TransactionDay: Identifiable, Sendable {
    public let date: CalendarDay
    public let transactions: [Transaction]
    public let income: Money
    public let expense: Money

    public var id: CalendarDay { date }
}

/// 交易頁(列表)的 model(parity.md「交易」)。
@MainActor
@Observable
public final class TransactionsModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// 起日，預設本月 1 號(台灣時間)。
    public var from: CalendarDay
    /// 迄日，預設今天(台灣時間)。
    public var to: CalendarDay
    public var scope: ViewScope = .all

    public private(set) var phase: Phase = .loading
    public private(set) var days: [TransactionDay] = []
    public private(set) var count = 0
    public private(set) var totalIncome = Money.zero
    /// 總支出不含「信用卡還款」(parity 刻意偏離第 26 項)。
    public private(set) var totalExpense = Money.zero

    public var net: Money { totalIncome - totalExpense }

    @ObservationIgnored private let repository: any TransactionRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private var loadedVersion: Int?

    public init(
        repository: any TransactionRepository,
        dataVersion: DataVersion,
        today: () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        self.dataVersion = dataVersion
        let now = today()
        from = now.firstOfMonth
        to = now
    }

    /// 依目前的起迄日與視角，抓齊區間內的所有交易紀錄。
    public func load() async {
        let version = dataVersion.value
        do {
            let transactions = try await repository.allTransactions(from: from, to: to, scope: scope)
            apply(transactions)
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

    private func apply(_ transactions: [Transaction]) {
        var order: [CalendarDay] = []
        var byDay: [CalendarDay: [Transaction]] = [:]
        for transaction in transactions {
            if byDay[transaction.date] == nil { order.append(transaction.date) }
            byDay[transaction.date, default: []].append(transaction)
        }
        days = order.sorted(by: >).map { date in
            let items = byDay[date] ?? []
            return TransactionDay(date: date, transactions: items, income: Self.income(of: items), expense: Self.expense(of: items))
        }
        count = transactions.count
        totalIncome = Self.income(of: transactions)
        totalExpense = Self.expense(of: transactions)
    }

    private static func income(of transactions: [Transaction]) -> Money {
        transactions.filter { $0.type == .income }.reduce(.zero) { $0 + $1.amount }
    }

    /// 支出合計，不含「信用卡還款」:繳卡費只是把錢從銀行存款帳戶移到信用卡帳戶，算進來會跟刷卡重複。
    private static func expense(of transactions: [Transaction]) -> Money {
        transactions.filter { $0.type == .expense && !$0.isCreditCardRepayment }.reduce(.zero) { $0 + $1.amount }
    }
}
