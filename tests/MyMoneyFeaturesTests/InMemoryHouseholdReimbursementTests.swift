import Foundation
import MyMoneyDomain
import MyMoneyTestSupport
import Testing

/// 測試替身的報銷行為跟後端一樣(上游 d0424df):勾選的代墊明細被結清、立刻從待報銷明細移出,待報銷總額是剩下明細的加總。
@Suite("替身:勾選指定代墊明細的報銷")
struct InMemoryHouseholdReimbursementTests {
    private let me = InMemoryAuthRepository.Member.sample.user.id
    private let day = CalendarDay(year: 2026, month: 9, day: 29)

    private func advance(_ items: [(String, Int)]) -> HouseholdAdvance {
        HouseholdAdvance(
            memberID: me, memberName: "小明", totalAdvanced: Money(Decimal(items.map(\.1).reduce(0, +))), totalReimbursed: .zero,
            pendingReimbursement: Money(Decimal(items.map(\.1).reduce(0, +))),
            advanceItems: items.map {
                AdvanceItem(
                    id: TransactionID($0.0), date: day, category: .dining, note: $0.0, amount: Money(Decimal($0.1)),
                    accountName: "iOS 測試皮夾", accountKind: .cash
                )
            },
            reimbursementItems: [], receivingAccounts: []
        )
    }

    @Test("勾選的明細移出待報銷，待報銷總額是剩下明細的加總")
    func selectedItemsLeaveThePendingList() async throws {
        let repository = InMemoryHouseholdRepository.sample(advances: [advance([("a", 120), ("b", 250)])])

        _ = try await repository.reimburse(Reimbursement(
            memberID: me, fromAccountID: AccountID("fund"), toAccountID: AccountID("bank"), amount: Money(120), date: day,
            note: "", advanceIDs: [TransactionID("a")]
        ))

        let mine = try #require(try await repository.advances().first)
        #expect(mine.advanceItems.map(\.id.rawValue) == ["b"])
        #expect(mine.pendingReimbursement == Money(250))
        #expect(mine.totalReimbursed == Money(120))
    }

    @Test("沒有勾選時維持原本的算法:待報銷 = 累計代墊 − 已報銷")
    func withoutSelectionKeepsTheLegacyArithmetic() async throws {
        let repository = InMemoryHouseholdRepository.sample(advances: [advance([("a", 120), ("b", 250)])])

        _ = try await repository.reimburse(Reimbursement(
            memberID: me, fromAccountID: AccountID("fund"), toAccountID: AccountID("bank"), amount: Money(100), date: day, note: ""
        ))

        let mine = try #require(try await repository.advances().first)
        #expect(mine.advanceItems.count == 2)
        #expect(mine.pendingReimbursement == Money(270))
    }
}
