import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("總覽的帳戶卡:信用卡的代墊／私帳與未出帳／繳款日、點了看該帳戶的記帳(#190)")
struct OverviewAccountCardTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let defaults: UserDefaults

    init() {
        let suite = "OverviewAccountCardTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func loaded(_ accounts: [Account], scope: ViewScope = .all) async -> OverviewModel {
        let overview = OverviewModel(
            accounts: InMemoryAccountRepository(accounts: accounts, summary: SampleAccounts.summary),
            transactions: InMemoryTransactionRepository(transactions: []),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)),
            goals: InMemorySavingsGoalRepository(goals: []), dataVersion: DataVersion(), defaults: defaults, today: { today },
            locale: Locale(identifier: "zh_Hant_TW")
        )
        overview.scope = scope
        await overview.load()
        return overview
    }

    private func card(
        billed: Int, unbilled: Int = 0, shared: Int = 0, personal: Int = 0, dueDay: Int? = 5, joint: Bool = false,
        owner: String? = nil, masked: Bool = false
    ) -> Account {
        .creditCard(
            CreditCard(
                id: AccountID("card"), name: "測試卡", colorHex: "#FFD4A0", billedDebt: Money(Decimal(billed)),
                unbilledDebt: Money(Decimal(unbilled)), creditLimit: nil, statementDay: nil, paymentDueDay: dueDay,
                sharedDebt: Money(Decimal(shared)), personalDebt: Money(Decimal(personal)), isJointFund: joint, ownerName: owner,
                isMasked: masked
            )
        )
    }

    @Test("信用卡多兩行:「代墊 X・私帳 Y」與「未出帳 X・每月 N 日繳款」,數字取後端值")
    func creditCardLines() async throws {
        let overview = await loaded([card(billed: 12000, unbilled: 3500, shared: 3000, personal: 12500)])

        let creditCard = try #require(overview.accountCards.first)
        #expect(creditCard.detailLines == ["代墊 $3,000・私帳 $12,500", "未出帳 $3,500・每月 5 日繳款"])
        #expect(creditCard.amount == Money(15500))
        #expect(creditCard.spokenText == "測試卡，個人私帳，信用卡待繳總額 15,500 元，代墊 3,000 元，私帳 12,500 元，未出帳 3,500 元，每月 5 日繳款")
    }

    @Test("沒有設定繳款日:第二行只有未出帳")
    func creditCardWithoutDueDay() async throws {
        let overview = await loaded([card(billed: 100, unbilled: 50, dueDay: nil)])

        let creditCard = try #require(overview.accountCards.first)
        #expect(creditCard.detailLines == ["代墊 $0・私帳 $0", "未出帳 $50"])
    }

    @Test("已全數結清:第一行寫「已全數結清」,第二行只有繳款日")
    func settledCreditCard() async throws {
        let overview = await loaded([card(billed: 0)])

        let creditCard = try #require(overview.accountCards.first)
        #expect(creditCard.detailLines == ["已全數結清", "每月 5 日繳款"])
        #expect(creditCard.spokenText == "測試卡，個人私帳，信用卡待繳總額 0 元，已全數結清，每月 5 日繳款")
    }

    @Test("公帳範圍裡的個人卡是「私卡代墊」,不拆代墊與私帳;他人的卡脫敏,寫持卡人")
    func privateCardAdvanceLines() async throws {
        let own = await loaded([card(billed: 0, unbilled: 1200, shared: 1200)], scope: .household)
        #expect(try #require(own.accountCards.first).detailLines == ["私卡代墊", "每月 5 日繳款"])

        let others = await loaded([card(billed: 0, unbilled: 1200, shared: 1200, owner: "小美", masked: true)], scope: .household)
        #expect(try #require(others.accountCards.first).detailLines == ["私卡代墊・持卡人 小美", "每月 5 日繳款"])

        let joint = await loaded([card(billed: 1000, unbilled: 0, shared: 1000, joint: true)], scope: .household)
        #expect(try #require(joint.accountCards.first).detailLines == ["代墊 $1,000・私帳 $0", "未出帳 $0・每月 5 日繳款"], "家庭信用卡不是私卡代墊")
    }

    @Test("現金與活存帳戶只有一行歸屬:家庭公帳或個人私帳")
    func cashAndBankLines() async throws {
        let personal = BankAccount(id: AccountID("b1"), name: "薪轉", colorHex: "#A8D8EA", balance: Money(100), isJointFund: false)
        let shared = BankAccount(id: AccountID("b2"), name: "共同基金", colorHex: "#A8D8EA", balance: Money(200), isJointFund: true)
        let wallet = CashWallet(id: AccountID("w1"), name: "皮夾", colorHex: "#10B981", balance: Money(300), isJointFund: false)
        let overview = await loaded([.bank(personal), .bank(shared), .cash(wallet)])

        let lines = Dictionary(uniqueKeysWithValues: overview.accountCards.map { ($0.name, $0.detailLines) })
        #expect(lines == ["薪轉": ["個人私帳"], "共同基金": ["家庭公帳"], "皮夾": ["個人私帳"]])
    }

    @Test("點帳戶卡要帶入該帳戶的記帳篩選:帳戶 ID 與名稱")
    func choiceForTheTransactionsFilter() async throws {
        let overview = await loaded([card(billed: 100)])

        let creditCard = try #require(overview.accountCards.first)
        #expect(creditCard.choice == AccountChoice(id: AccountID("card"), name: "測試卡"))
    }
}
