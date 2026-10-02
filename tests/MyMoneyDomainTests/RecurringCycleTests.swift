import MyMoneyDomain
import Testing

@Suite("週期收支的繳費月份(上游 ADR 0012，W:Recurring.tsx 的 handleCycleChange)")
struct RecurringCycleTests {
    @Test("每個週期可選的繳費月份:月繳固定 1;雙月繳 1–2;季繳 1–3;半年繳 1–6;年繳 1–12")
    func monthChoices() {
        #expect(RecurringCycle.monthly.monthChoices == [1])
        #expect(RecurringCycle.bimonthly.monthChoices == [1, 2])
        #expect(RecurringCycle.quarterly.monthChoices == [1, 2, 3])
        #expect(RecurringCycle.semiannual.monthChoices == Array(1...6))
        #expect(RecurringCycle.annual.monthChoices == Array(1...12))
    }

    @Test("切換週期時，不在新週期範圍內的月份重設為第一項，範圍內的保留;月繳一律 1", arguments: [
        (RecurringCycle.monthly, 5, 1), (.monthly, 1, 1),
        (.bimonthly, 2, 2), (.bimonthly, 3, 1), (.bimonthly, 12, 1),
        (.quarterly, 3, 3), (.quarterly, 4, 1),
        (.semiannual, 6, 6), (.semiannual, 7, 1),
        (.annual, 12, 12), (.annual, 0, 1), (.annual, 13, 1),
    ])
    func clamping(cycle: RecurringCycle, month: Int, expected: Int) {
        #expect(cycle.clampedMonth(month) == expected)
    }
}
