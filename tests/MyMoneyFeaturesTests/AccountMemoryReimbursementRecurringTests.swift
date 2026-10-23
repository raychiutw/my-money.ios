import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 報銷撥款帳戶、收款帳戶、週期收支關聯帳戶的帳戶記憶(#279):各自記憶,只在使用者主動選過帳戶之後才帶入。
@MainActor
@Suite("帳戶記憶:報銷與週期收支")
struct AccountMemoryReimbursementRecurringTests {
    private let suite = "AccountMemoryRR-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    private let me = InMemoryAuthRepository.Member.sample.user.id
    private let today = CalendarDay(year: 2026, month: 9, day: 29)
    private let dataVersion = DataVersion()
    private let fund = AccountID("fund")

    private var advance: HouseholdAdvance {
        HouseholdAdvance(
            memberID: me, memberName: "小明", totalAdvanced: Money(700), totalReimbursed: .zero, pendingReimbursement: Money(700),
            advanceItems: [], reimbursementItems: [],
            receivingAccounts: [ReceivingAccount(id: SampleAccounts.savings.id, name: SampleAccounts.savings.name, kind: .bank)]
        )
    }

    private func reimbursement() async -> ReimbursementModel {
        let accounts = InMemoryAccountRepository(accounts: [
            .bank(BankAccount(id: fund, name: "家庭共同基金", colorHex: "#A8D8EA", balance: Money(8000), isJointFund: true)),
            .bank(SampleAccounts.savings),
        ], summary: .zero)
        let household = HouseholdModel(
            repository: InMemoryHouseholdRepository.sample(advances: [advance]), accounts: accounts, currentUser: me,
            context: SessionContext(dataVersion: dataVersion, defaults: defaults, today: { today }, userID: me)
        )
        await household.load()
        let model = household.makeReimbursement(for: advance)
        await model.load()
        return model
    }

    @Test("報銷:送出成功後撥款帳戶與收款帳戶各自記住,下次帶入;沒記過是空白")
    func reimbursementRemembers() async {
        defaults.removePersistentDomain(forName: suite)
        let first = await reimbursement()
        #expect(first.fromAccountID == nil && first.toAccountID == nil)
        first.fromAccountID = fund
        first.toAccountID = SampleAccounts.savings.id
        #expect(await first.submit() != nil)

        let next = await reimbursement()
        #expect(next.fromAccountID == fund)
        #expect(next.toAccountID == SampleAccounts.savings.id)
    }

    @Test("報銷:記住的收款帳戶不是這位成員的可收款帳戶:收款帳戶留白")
    func receivingFromAnotherMemberIsIgnored() async {
        defaults.removePersistentDomain(forName: suite)
        AccountMemory(defaults: defaults, userID: me, purpose: .reimbursementReceiving).remember(AccountID("someone-elses"))
        let model = await reimbursement()
        #expect(model.toAccountID == nil)
    }

    private func editor(adding: Bool = true) async -> RecurringEditorModel {
        let model = RecurringEditorModel(
            adding: (), repository: InMemoryRecurringRepository.sample(), accounts: InMemoryAccountRepository.sample(),
            dataVersion: dataVersion, accountMemory: AccountMemory(defaults: defaults, userID: me, purpose: .recurring)
        )
        await model.prepare()
        return model
    }

    @Test("週期收支:主動選過關聯帳戶並儲存後,下次新增帶入;沒選過維持「無特定帳戶」")
    func recurringRemembers() async {
        defaults.removePersistentDomain(forName: suite)
        let first = await editor()
        #expect(first.accountID == nil)
        first.name = "房租"
        first.amountText = "100"
        first.accountID = SampleAccounts.savings.id
        #expect(await first.save())

        #expect(await editor().accountID == SampleAccounts.savings.id)
    }

    @Test("週期收支:儲存時選「無特定帳戶」不覆蓋記憶")
    func recurringNoneDoesNotOverwrite() async {
        defaults.removePersistentDomain(forName: suite)
        AccountMemory(defaults: defaults, userID: me, purpose: .recurring).remember(SampleAccounts.savings.id)
        let model = await editor()
        model.accountID = nil
        model.name = "雜項"
        model.amountText = "50"
        #expect(await model.save())
        #expect(await editor().accountID == SampleAccounts.savings.id)
    }

    @Test("週期收支:第一次載入帳戶失敗,重試成功後仍帶入記住的帳戶(code review)")
    func recurringRecallsAfterFailedLoadThenRetry() async {
        defaults.removePersistentDomain(forName: suite)
        AccountMemory(defaults: defaults, userID: me, purpose: .recurring).remember(SampleAccounts.savings.id)
        let accounts = InMemoryAccountRepository.sample()
        let model = RecurringEditorModel(
            adding: (), repository: InMemoryRecurringRepository.sample(), accounts: accounts,
            dataVersion: dataVersion, accountMemory: AccountMemory(defaults: defaults, userID: me, purpose: .recurring)
        )
        await accounts.fail(with: .unreadableResponse)
        await model.prepare()
        #expect(model.accountID == nil)

        await accounts.recover()
        await model.prepare()
        #expect(model.accountID == SampleAccounts.savings.id)
    }
}
