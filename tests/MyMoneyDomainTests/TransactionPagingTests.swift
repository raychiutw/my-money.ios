import Foundation
import MyMoneyDomain
import Synchronization
import Testing

@Suite("交易記錄用 limit / offset 分頁抓齊")
struct TransactionPagingTests {
    /// 只會分頁回應的假 repository:記下每一次的 limit 與 offset。
    private final class PagedRepository: TransactionRepository {
        let total: Int
        private let calls = Mutex<[(limit: Int, offset: Int)]>([])

        init(total: Int) {
            self.total = total
        }

        var requestedPages: [(limit: Int, offset: Int)] {
            calls.withLock { $0 }
        }

        func transactions(
            from: CalendarDay?, to: CalendarDay?, scope: ViewScope, limit: Int, offset: Int
        ) async throws -> [Transaction] {
            calls.withLock { $0.append((limit, offset)) }
            let upper = min(offset + limit, total)
            guard offset < upper else { return [] }
            return (offset..<upper).map { index in
                Transaction(
                    id: TransactionID("t\(index)"),
                    accountID: AccountID("a"),
                    accountName: nil,
                    type: .expense,
                    category: .dining,
                    amount: Money(1),
                    note: "",
                    date: CalendarDay(year: 2026, month: 9, day: 1),
                    isShared: true,
                    recorderName: nil
                )
            }
        }

        func create(_ draft: TransactionDraft) async throws {}
        func update(_ id: TransactionID, with draft: TransactionDraft) async throws {}
        func delete(_ id: TransactionID) async throws {}
        func exportCSV(from: CalendarDay, to: CalendarDay) async throws -> Data { Data() }
    }

    private let september = (CalendarDay(year: 2026, month: 9, day: 1), CalendarDay(year: 2026, month: 9, day: 30))

    /// web 以前沒帶 limit,後端只回 50 筆;`79edd20` 改帶 200,超過 200 仍會被截斷(parity 刻意偏離第 1 項)。
    @Test("超過一頁時繼續抓，直到回傳筆數少於一頁")
    func fetchesEveryPage() async throws {
        let repository = PagedRepository(total: 450)

        let all = try await repository.allTransactions(from: september.0, to: september.1, scope: .all, pageSize: 200)

        #expect(all.count == 450)
        #expect(repository.requestedPages.map(\.offset) == [0, 200, 400])
        #expect(repository.requestedPages.allSatisfy { $0.limit == 200 })
    }

    @Test("剛好整頁時，再抓一次空頁確認已經抓完")
    func exactMultipleOfPageSize() async throws {
        let repository = PagedRepository(total: 400)

        let all = try await repository.allTransactions(from: september.0, to: september.1, scope: .all, pageSize: 200)

        #expect(all.count == 400)
        #expect(repository.requestedPages.map(\.offset) == [0, 200, 400])
    }

    @Test("不到一頁時只抓一次")
    func singlePage() async throws {
        let repository = PagedRepository(total: 3)

        let all = try await repository.allTransactions(from: september.0, to: september.1, scope: .all, pageSize: 200)

        #expect(all.count == 3)
        #expect(repository.requestedPages.count == 1)
    }
}
