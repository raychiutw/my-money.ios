import Foundation

/// 交易記錄(`/transactions`)。
public protocol TransactionRepository: Sendable {
    /// 一頁收支明細，順序照後端(日期由新到舊)。起日或迄日是 `nil` 時不限;`accountID` 是 `nil` 時不限帳戶(上游 ADR 0019)。
    func transactions(
        from: CalendarDay?, to: CalendarDay?, scope: ViewScope, accountID: AccountID?, limit: Int, offset: Int
    ) async throws -> [Transaction]

    func create(_ draft: TransactionDraft) async throws

    /// 家人記的也能編輯。「信用卡還款」的紀錄後端會拒絕(400)。
    func update(_ id: TransactionID, with draft: TransactionDraft) async throws

    /// 「信用卡還款」的紀錄後端會拒絕(400)。
    func delete(_ id: TransactionID) async throws

    /// 起迄日內我記的交易記錄的 CSV(`GET /export/csv`,UTF-8 加 BOM),原樣回傳。
    func exportCSV(from: CalendarDay, to: CalendarDay) async throws -> Data
}

extension TransactionRepository {
    /// 不指定帳戶的一頁收支明細。
    public func transactions(
        from: CalendarDay?, to: CalendarDay?, scope: ViewScope, limit: Int, offset: Int
    ) async throws -> [Transaction] {
        try await transactions(from: from, to: to, scope: scope, accountID: nil, limit: limit, offset: offset)
    }

    /// 區間內的所有交易記錄：用 limit / offset 一路抓到回傳筆數少於一頁為止。
    public func allTransactions(
        from: CalendarDay, to: CalendarDay, scope: ViewScope, accountID: AccountID? = nil, pageSize: Int = 200
    ) async throws -> [Transaction] {
        var all: [Transaction] = []
        var offset = 0
        while true {
            let page = try await transactions(
                from: from, to: to, scope: scope, accountID: accountID, limit: pageSize, offset: offset
            )
            all += page
            guard page.count == pageSize else { return all }
            offset += pageSize
        }
    }
}
