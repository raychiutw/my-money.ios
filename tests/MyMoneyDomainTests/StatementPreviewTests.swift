import Foundation
import MyMoneyDomain
import Testing

@Suite("出帳預覽:切換延期後的試算(上游 ADR 0024)")
struct StatementPreviewTests {
    private func item(
        _ id: String, _ kind: StatementItem.Kind, _ amount: Int, shared: Bool = false,
        priorDeferred: Bool = false, initiallyDeferred: Bool = false
    ) -> StatementItem {
        StatementItem(
            id: TransactionID(id), kind: kind, amount: Money(Decimal(amount)),
            date: CalendarDay(year: 2026, month: 10, day: 10), category: TransactionCategory("餐飲"), note: id,
            isShared: shared, isPriorDeferred: priorDeferred, isInitiallyDeferred: initiallyDeferred
        )
    }

    /// 數字取自 prod 錄下的真實預覽:本期午餐 1200、刷退 300、延期的 800、上期延入 500;已出帳基準 400、未出帳基準 150。
    private func preview(extra: [StatementItem] = [], repay: Int = 0) -> StatementPreview {
        StatementPreview(
            statementDate: CalendarDay(year: 2026, month: 10, day: 15),
            previousStatementDate: CalendarDay(year: 2026, month: 9, day: 15),
            items: [
                item("deferred", .expense, 800, initiallyDeferred: true),
                item("refund", .refund, 300),
                item("lunch", .expense, 1200),
                item("prior", .expense, 500, priorDeferred: true),
            ] + extra,
            baseNetBilled: Money(400), totalRepay: Money(Decimal(repay)), baseNetUnbilled: Money(150),
            hasRolledCycle: false, priorDeferredCount: 1
        )
    }

    @Test("開窗時的延期集合是後端標的 is_initially_deferred;上期延入款首次結算預設納入，不在裡面")
    func initiallyDeferred() {
        #expect(preview().initiallyDeferredIDs == [TransactionID("deferred")])
    }

    @Test("維持開窗時的延期:跟後端預覽的數字一樣(出帳淨額 1400、出帳後待繳 1800、剩餘未出帳 950)")
    func matchesTheBackendPreview() {
        let outlook = preview().outlook(deferring: [TransactionID("deferred")])

        #expect(outlook.expense == Money(1700))
        #expect(outlook.expenseCount == 2)
        #expect(outlook.refund == Money(300))
        #expect(outlook.refundCount == 1)
        #expect(outlook.net == Money(1400))
        #expect(outlook.projectedBilled == Money(1800))
        #expect(outlook.projectedUnbilled == Money(950))
        #expect(outlook.deferredCount == 1)
    }

    @Test("再多延一筆:出帳淨額變少，延期的金額回到剩餘未出帳")
    func deferringMoreMovesMoneyToUnbilled() {
        let outlook = preview().outlook(deferring: [TransactionID("deferred"), TransactionID("lunch")])

        #expect(outlook.expense == Money(500))
        #expect(outlook.net == Money(200))
        #expect(outlook.projectedBilled == Money(600))
        #expect(outlook.projectedUnbilled == Money(2150))
        #expect(outlook.deferredCount == 2)
    }

    @Test("取消延期:原本延期的那筆納入本期")
    func undeferring() {
        let outlook = preview().outlook(deferring: [])

        #expect(outlook.expense == Money(2500))
        #expect(outlook.net == Money(2200))
        #expect(outlook.projectedBilled == Money(2600))
        #expect(outlook.projectedUnbilled == Money(150))
        #expect(outlook.deferredCount == 0)
    }

    @Test("刷退比消費多:出帳淨額最小是 0，但出帳後待繳款照差額扣(跟 web 一樣)")
    func refundExceedsExpense() {
        let outlook = preview().outlook(deferring: [TransactionID("deferred"), TransactionID("lunch"), TransactionID("prior")])

        #expect(outlook.net == .zero)
        #expect(outlook.projectedBilled == Money(100))
    }

    @Test("出帳後待繳款扣掉已沖抵的還款，最小是 0")
    func repaymentIsDeducted() {
        #expect(preview(repay: 1000).outlook(deferring: [TransactionID("deferred")]).projectedBilled == Money(800))
        #expect(preview(repay: 9000).outlook(deferring: [TransactionID("deferred")]).projectedBilled == .zero)
    }

    @Test("公私帳拆解:家庭公帳代墊是納入本期的公帳消費，個人私帳是出帳淨額扣掉它")
    func debtSplit() {
        let shared = item("family", .expense, 600, shared: true)
        let outlook = preview(extra: [shared]).outlook(deferring: [TransactionID("deferred")])

        #expect(outlook.net == Money(2000))
        #expect(outlook.sharedDebt == Money(600))
        #expect(outlook.personalDebt == Money(1400))

        let deferredShared = preview(extra: [shared]).outlook(deferring: [TransactionID("deferred"), TransactionID("family")])
        #expect(deferredShared.sharedDebt == .zero)
    }
}
