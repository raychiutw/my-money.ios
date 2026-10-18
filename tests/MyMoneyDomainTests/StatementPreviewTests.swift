import Foundation
import MyMoneyDomain
import Testing

@Suite("出帳預覽:切換延期後的試算(上游 ADR 0024、0029、0030)")
struct StatementPreviewTests {
    private func day(_ month: Int, _ day: Int) -> CalendarDay { CalendarDay(year: 2026, month: month, day: day) }

    private func item(
        _ id: String, _ kind: StatementItem.Kind, _ amount: Int, on date: CalendarDay? = nil, shared: HouseholdPayment? = nil,
        priorDeferred: Bool = false, initiallyDeferred: Bool = false
    ) -> StatementItem {
        StatementItem(
            id: TransactionID(id), kind: kind, amount: Money(Decimal(amount)), date: date ?? day(9, 20),
            category: TransactionCategory("餐飲"), note: id, isShared: shared != nil, householdPayment: shared,
            isPriorDeferred: priorDeferred, isInitiallyDeferred: initiallyDeferred
        )
    }

    /// 數字取自 prod 錄下的真實預覽(結帳日 25 號、今天 10/17,結算 8/26～9/25):本期晚餐 600(公帳)、交通 400(公帳)、
    /// 個人購物 300、公帳刷退 100、上期延入 250(8/20);已出帳基準 0、未出帳基準 150(結帳日之後的一筆,1 筆)。
    private func preview(
        dinner: HouseholdPayment = .advancePending, traffic: HouseholdPayment = .advancePending, repay: Int = 0
    ) -> StatementPreview {
        StatementPreview(
            startDate: day(8, 26), endDate: day(9, 25), isStatementPending: true,
            items: [
                item("refund", .refund, 100, on: day(9, 20), shared: .advancePending),
                item("private", .expense, 300, on: day(9, 14)),
                item("traffic", .expense, 400, on: day(9, 12), shared: traffic),
                item("dinner", .expense, 600, on: day(9, 10), shared: dinner),
                item("prior", .expense, 250, on: day(8, 20), priorDeferred: true),
            ],
            baseNetBilled: Money(0), totalRepay: Money(Decimal(repay)), baseNetUnbilled: Money(150), baseUnbilledCount: 1,
            hasRolledCycle: false, priorDeferredCount: 1
        )
    }

    @Test("開窗時的延期集合是後端標的 is_initially_deferred;上期延入款預設納入本期，不在裡面")
    func initiallyDeferred() {
        let withDeferred = StatementPreview(
            startDate: day(8, 26), endDate: day(9, 25), items: [
                item("a", .expense, 100, initiallyDeferred: true), item("b", .expense, 100), item("c", .expense, 100, priorDeferred: true),
            ],
            baseNetBilled: .zero, totalRepay: .zero, baseNetUnbilled: .zero
        )
        #expect(withDeferred.initiallyDeferredIDs == [TransactionID("a")])
    }

    @Test("維持開窗時的延期:跟後端預覽的數字一樣(出帳淨額 1450、出帳後待繳 1450、剩餘未出帳 150、公帳 900、私帳 550)")
    func matchesTheBackendPreview() {
        let outlook = preview().outlook(deferring: [])

        #expect(outlook.expense == Money(1550))
        #expect(outlook.expenseCount == 4)
        #expect(outlook.refund == Money(100))
        #expect(outlook.refundCount == 1)
        #expect(outlook.net == Money(1450))
        #expect(outlook.projectedBilled == Money(1450))
        #expect(outlook.projectedUnbilled == Money(150))
        #expect(outlook.sharedDebt == Money(900), "公帳 600 + 400 − 刷退 100")
        #expect(outlook.personalDebt == Money(550))
        #expect(outlook.deferredCount == 0)
    }

    @Test("四層摘要的來源:本期新增 − 本期延後 + 上期延入 = 本期出帳淨額;新增與上期延入是固定值，不隨延期變")
    func sourceIdentity() {
        for deferring in [Set<TransactionID>(), [TransactionID("dinner")], [TransactionID("prior")], [TransactionID("dinner"), TransactionID("prior"), TransactionID("refund")]] {
            let outlook = preview().outlook(deferring: deferring)

            #expect(outlook.newInCycle == Money(1200), "交易日在 8/26～9/25 內:600 + 400 + 300 − 100")
            #expect(outlook.newInCycleCount == 4)
            #expect(outlook.priorIncoming == Money(250))
            #expect(outlook.priorIncomingCount == 1)
            #expect(outlook.newInCycle - outlook.deferred + outlook.priorIncoming == outlook.net || outlook.net == .zero,
                    "\(deferring):恆等式不成立")
        }
    }

    @Test("再延一筆:出帳淨額變少，延期的金額回到剩餘未出帳，筆數也加上")
    func deferringMovesMoneyToUnbilled() {
        let outlook = preview().outlook(deferring: [TransactionID("dinner")])

        #expect(outlook.net == Money(850))
        #expect(outlook.deferred == Money(600))
        #expect(outlook.deferredCount == 1)
        #expect(outlook.projectedUnbilled == Money(750), "150 + 600")
        #expect(outlook.remainingUnbilledCount == 2, "結帳日之後 1 筆 + 本次延後 1 筆")
        #expect(outlook.projectedBilled == Money(850))
    }

    @Test("把上期延入款再延一次:本期延後算它，上期延入的固定值不變")
    func deferringAPriorItemAgain() {
        let outlook = preview().outlook(deferring: [TransactionID("prior")])

        #expect(outlook.net == Money(1200))
        #expect(outlook.deferred == Money(250))
        #expect(outlook.priorIncoming == Money(250))
        #expect(outlook.projectedUnbilled == Money(400))
    }

    @Test("公帳已由家庭報銷:不計入家庭公帳代墊，全額轉列個人私帳(出帳淨額不變)")
    func reimbursedSharedItemsMoveToPersonal() {
        let outlook = preview(dinner: .advanceReimbursed).outlook(deferring: [])

        #expect(outlook.net == Money(1450), "卡片待繳款仍要與銀行帳單吻合")
        #expect(outlook.sharedDebt == Money(300), "只剩交易 400 − 刷退 100")
        #expect(outlook.personalDebt == Money(1150))
    }

    @Test("已額外處理的公帳同樣不計入家庭公帳代墊;全部報銷或處理後公帳是 0")
    func handledSeparatelyIsNotSharedDebt() {
        let outlook = preview(dinner: .advanceReimbursed, traffic: .advanceHandledSeparately).outlook(deferring: [])

        #expect(outlook.sharedDebt == .zero, "刷退 100 比剩下的公帳 0 多:最小是 0")
        #expect(outlook.personalDebt == Money(1450))
    }

    @Test("公帳刷退優先折抵公帳欠款;延期掉的公帳明細不算")
    func sharedRefundOffsetsSharedDebt() {
        let outlook = preview().outlook(deferring: [TransactionID("dinner"), TransactionID("refund")])

        #expect(outlook.sharedDebt == Money(400), "延期的刷退不折抵，延期的晚餐不計入")
    }

    @Test("刷退比消費多:出帳淨額最小是 0，但出帳後待繳款照差額扣(跟 web 一樣)")
    func refundExceedsExpense() {
        let outlook = preview().outlook(deferring: [TransactionID("dinner"), TransactionID("traffic"), TransactionID("private"), TransactionID("prior")])

        #expect(outlook.net == .zero)
        #expect(outlook.projectedBilled == .zero, "0 + (0 − 100) 最小是 0")
    }

    @Test("出帳後待繳款扣掉已沖抵的還款，最小是 0")
    func repaymentIsDeducted() {
        #expect(preview(repay: 1000).outlook(deferring: []).projectedBilled == Money(450))
        #expect(preview(repay: 9000).outlook(deferring: []).projectedBilled == .zero)
    }
}
