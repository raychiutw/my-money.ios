import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 報銷沖帳逐筆勾選(上游 d0424df、42149e7;#241):待報銷明細依墊付帳戶分組、預設全選、金額 = 勾選明細加總。
@MainActor
@Suite("報銷沖帳的勾選")
struct ReimbursementSelectionTests {
    private let dataVersion = DataVersion()
    private let me = InMemoryAuthRepository.Member.sample.user.id
    private let today = CalendarDay(year: 2026, month: 9, day: 29)

    /// 三筆待報銷:皮夾 120 與 80(現金)、信用卡 500。
    private var advance: HouseholdAdvance {
        func item(_ id: String, _ amount: Int, _ account: String, _ kind: AccountKind?) -> AdvanceItem {
            AdvanceItem(
                id: TransactionID(id), date: today, category: .dining, note: id, amount: Money(Decimal(amount)),
                accountName: account, accountKind: kind
            )
        }
        return HouseholdAdvance(
            memberID: me, memberName: "小明", totalAdvanced: Money(700), totalReimbursed: .zero, pendingReimbursement: Money(700),
            advanceItems: [item("a", 120, "iOS 測試皮夾", .cash), item("b", 500, "iOS 信用卡", .creditCard), item("c", 80, "iOS 測試皮夾", .cash)],
            reimbursementItems: [],
            receivingAccounts: [ReceivingAccount(id: SampleAccounts.savings.id, name: SampleAccounts.savings.name, kind: .bank)]
        )
    }

    private func make(
        _ advance: HouseholdAdvance, repository: InMemoryHouseholdRepository? = nil
    ) async -> (ReimbursementModel, InMemoryHouseholdRepository) {
        let repository = repository ?? InMemoryHouseholdRepository.sample(advances: [advance])
        let accounts = InMemoryAccountRepository(accounts: [
            .bank(BankAccount(id: AccountID("fund"), name: "家庭共同基金", colorHex: "#A8D8EA", balance: Money(8000), isJointFund: true)),
            .bank(SampleAccounts.savings),
        ], summary: .zero)
        let household = HouseholdModel(
            repository: repository, accounts: accounts, currentUser: me, dataVersion: dataVersion, today: { today }
        )
        await household.load()
        let model = household.makeReimbursement(for: advance)
        await model.load()
        model.fromAccountID = AccountID("fund")
        model.toAccountID = SampleAccounts.savings.id
        return (model, repository)
    }

    @Test("預設全選;金額是勾選明細的加總;明細依墊付帳戶分組(順序照第一次出現)")
    func defaults() async {
        let (model, _) = await make(advance)

        #expect(model.usesItemSelection)
        #expect(model.selectedAmount == Money(700))
        #expect(model.amountText == "700")
        #expect(model.groups.map(\.title) == ["iOS 測試皮夾", "iOS 信用卡"])
        #expect(model.groups.map(\.subtotal) == [Money(200), Money(500)])
        #expect(model.groups.map(\.items.count) == [2, 1])
        #expect(model.groups.allSatisfy { $0.isFullySelected })
        #expect(model.hasMultipleGroups)
    }

    @Test("逐筆勾選:取消一筆金額減少，再勾回來金額回復")
    func toggleItem() async {
        let (model, _) = await make(advance)

        model.toggle(TransactionID("b"))
        #expect(model.selectedAmount == Money(200))
        #expect(model.amountText == "200")
        #expect(!model.isSelected(TransactionID("b")))
        #expect(model.groups[1].selectedCount == 0)

        model.toggle(TransactionID("b"))
        #expect(model.selectedAmount == Money(700))
    }

    @Test("整組勾選或取消;只勾一部分時整組不算全選")
    func toggleGroup() async {
        let (model, _) = await make(advance)
        let wallet = model.groups[0].id

        model.setGroup(wallet, selected: false)
        #expect(model.selectedAmount == Money(500))
        model.toggle(TransactionID("a"))
        #expect(model.groups[0].selectedCount == 1)
        #expect(!model.groups[0].isFullySelected)

        model.setGroup(wallet, selected: true)
        #expect(model.selectedAmount == Money(700))
        #expect(model.groups[0].isFullySelected)
    }

    @Test("「僅選此帳戶」:清空其他帳戶、只保留該帳戶的全部")
    func selectOnlyThisAccount() async {
        let (model, _) = await make(advance)

        model.selectOnly(model.groups[1].id)
        #expect(model.selectedAmount == Money(500))
        #expect(model.isSelected(TransactionID("b")))
        #expect(!model.isSelected(TransactionID("a")))

        model.selectOnly(model.groups[0].id)
        #expect(model.selectedAmount == Money(200))
    }

    @Test("名稱相同但類型不同的帳戶不併成一組")
    func sameNameDifferentKind() async {
        var items = advance.advanceItems
        items.append(AdvanceItem(
            id: TransactionID("d"), date: today, category: .dining, note: "d", amount: Money(10),
            accountName: "iOS 測試皮夾", accountKind: .bank
        ))
        let tricky = HouseholdAdvance(
            memberID: me, memberName: "小明", totalAdvanced: Money(710), totalReimbursed: .zero, pendingReimbursement: Money(710),
            advanceItems: items, reimbursementItems: [], receivingAccounts: advance.receivingAccounts
        )
        let (model, _) = await make(tricky)

        #expect(model.groups.count == 3)
    }

    @Test("只有一個墊付帳戶:不需要分組操作")
    func singleGroup() async {
        let single = HouseholdAdvance(
            memberID: me, memberName: "小明", totalAdvanced: Money(200), totalReimbursed: .zero, pendingReimbursement: Money(200),
            advanceItems: Array(advance.advanceItems.filter { $0.accountName == "iOS 測試皮夾" }), reimbursementItems: [],
            receivingAccounts: advance.receivingAccounts
        )
        let (model, _) = await make(single)

        #expect(model.groups.count == 1)
        #expect(!model.hasMultipleGroups)
    }

    @Test("全部取消勾選:不能送出，也不打 API")
    func nothingSelected() async {
        let (model, repository) = await make(advance)
        for group in model.groups { model.setGroup(group.id, selected: false) }

        #expect(model.selectedAmount == .zero)
        #expect(!model.canSubmit)
        #expect(await model.submit() == nil)
        #expect(model.errorMessage == "請至少勾選一筆要報銷的代墊明細")
        #expect(await repository.reimbursements.isEmpty)
    }

    @Test("送出:帶被勾選明細的 ID(依明細順序)與勾選的加總金額;被結清的明細從待報銷移出")
    func submitsSelection() async throws {
        let (model, repository) = await make(advance)
        model.toggle(TransactionID("b"))

        let message = await model.submit()

        #expect(message == "成功從共同基金撥款報銷 NT$ 200 給 小明！")
        let sent = try #require(await repository.reimbursements.first)
        #expect(sent.amount == Money(200))
        #expect(sent.advanceIDs == [TransactionID("a"), TransactionID("c")])
        let remaining = try #require(try await repository.advances().first)
        #expect(remaining.advanceItems.map(\.id.rawValue) == ["b"])
        #expect(dataVersion.value == 1)
    }

    @Test("沒有明細的待報銷(例如舊資料):維持手動輸入金額，不帶 advance_ids")
    func legacyManualAmount() async {
        let manual = HouseholdAdvance(
            memberID: me, memberName: "小明", totalAdvanced: Money(600), totalReimbursed: .zero, pendingReimbursement: Money(600),
            advanceItems: [], reimbursementItems: [], receivingAccounts: advance.receivingAccounts
        )
        let (model, repository) = await make(manual)

        #expect(!model.usesItemSelection)
        #expect(model.amountText == "600")
        model.amountText = "0"
        #expect(await model.submit() == nil)
        #expect(model.errorMessage == "請輸入有效的報銷金額")
        model.amountText = "450"
        _ = await model.submit()
        #expect(await repository.reimbursements.first?.amount == Money(450))
        #expect(await repository.reimbursements.first?.advanceIDs == [])
    }
}
