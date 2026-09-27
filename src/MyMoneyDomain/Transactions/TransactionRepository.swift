/// 交易紀錄(`/transactions`)。
public protocol TransactionRepository: Sendable {
    /// 一頁交易紀錄，順序照後端(日期由新到舊)。
    func transactions(from: CalendarDay, to: CalendarDay, scope: ViewScope, limit: Int, offset: Int) async throws -> [Transaction]

    func create(_ draft: TransactionDraft) async throws
}

extension TransactionRepository {
    /// 區間內的所有交易紀錄：用 limit / offset 一路抓到回傳筆數少於一頁為止。
    public func allTransactions(
        from: CalendarDay, to: CalendarDay, scope: ViewScope, pageSize: Int = 200
    ) async throws -> [Transaction] {
        var all: [Transaction] = []
        var offset = 0
        while true {
            let page = try await transactions(from: from, to: to, scope: scope, limit: pageSize, offset: offset)
            all += page
            guard page.count == pageSize else { return all }
            offset += pageSize
        }
    }
}
