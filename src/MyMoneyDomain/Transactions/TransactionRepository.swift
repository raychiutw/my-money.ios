import Foundation

/// 交易紀錄(`/transactions`)。
public protocol TransactionRepository: Sendable {
    /// 一頁交易紀錄，順序照後端(日期由新到舊)。起日或迄日是 `nil` 時不限。
    func transactions(from: CalendarDay?, to: CalendarDay?, scope: ViewScope, limit: Int, offset: Int) async throws -> [Transaction]

    func create(_ draft: TransactionDraft) async throws

    /// 家人記的也能編輯。「信用卡還款」的紀錄後端會拒絕(400)。
    func update(_ id: TransactionID, with draft: TransactionDraft) async throws

    /// 「信用卡還款」的紀錄後端會拒絕(400)。
    func delete(_ id: TransactionID) async throws

    /// 起迄日內我記的交易紀錄的 CSV(`GET /export/csv`,UTF-8 加 BOM),原樣回傳。
    func exportCSV(from: CalendarDay, to: CalendarDay) async throws -> Data
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
