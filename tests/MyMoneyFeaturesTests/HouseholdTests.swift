import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("家庭群組")
struct HouseholdTests {
    private let dataVersion = DataVersion()

    private let me = InMemoryAuthRepository.Member.sample.user.id
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func loaded(
        _ repository: InMemoryHouseholdRepository, accounts: InMemoryAccountRepository = .sample()
    ) async -> HouseholdModel {
        let model = HouseholdModel(
            repository: repository, accounts: accounts, dataVersion: dataVersion, currentUserID: me, today: { today }
        )
        await model.load()
        return model
    }

    private func member(_ name: String, _ role: HouseholdRole) -> HouseholdMember {
        HouseholdMember(
            userID: UserID(name), name: name, email: "\(name)@example.com", role: role,
            joinedAt: try! Date("2026-09-27T21:20:20Z", strategy: .iso8601)
        )
    }

    /// 小美替家裡墊了 600,還沒報銷。
    private let meiAdvance = HouseholdAdvance(
        memberID: UserID("sample-mei"), memberName: "小美", totalAdvanced: Money(600), totalReimbursed: .zero,
        pendingReimbursement: Money(600), advanceItems: [], reimbursementItems: []
    )

    @Test("有家庭群組時一起載入代墊統計;沒有家庭群組時是空的")
    func loadsAdvances() async {
        let model = await loaded(.sample(advances: [InMemoryHouseholdRepository.myPendingAdvance, meiAdvance]))
        #expect(model.advances.map(\.memberName) == ["小明", "小美"])

        let without = await loaded(InMemoryHouseholdRepository(household: nil, advances: [meiAdvance]))
        #expect(without.advances.isEmpty)
    }

    @Test("代墊明細就地展開，可以同時展開多位成員")
    func detailsExpandIndependently() async {
        let model = await loaded(.sample(advances: [InMemoryHouseholdRepository.myPendingAdvance, meiAdvance]))

        model.toggleDetails(of: me)
        model.toggleDetails(of: UserID("sample-mei"))
        #expect(model.isShowingDetails(of: me) && model.isShowingDetails(of: UserID("sample-mei")))

        model.toggleDetails(of: me)
        #expect(!model.isShowingDetails(of: me))
        #expect(model.isShowingDetails(of: UserID("sample-mei")))
    }

    @Test("只能從共同基金報銷自己的代墊款;其他成員顯示原因，已結清的不能報銷")
    func onlyMyPendingAdvanceCanBeReimbursed() async {
        let model = await loaded(.sample(advances: [InMemoryHouseholdRepository.myPendingAdvance, meiAdvance]))

        #expect(model.canReimburse(InMemoryHouseholdRepository.myPendingAdvance))
        #expect(model.reimbursementNote(for: InMemoryHouseholdRepository.myPendingAdvance) == nil)
        #expect(!model.canReimburse(meiAdvance))
        #expect(model.reimbursementNote(for: meiAdvance) == "後端目前不提供其他成員的收款帳戶，請由小美本人撥款報銷。")

        let settled = HouseholdAdvance(
            memberID: me, memberName: "小明", totalAdvanced: Money(250), totalReimbursed: Money(250),
            pendingReimbursement: .zero, advanceItems: [], reimbursementItems: []
        )
        #expect(!model.canReimburse(settled))
    }

    /// 家庭共同基金兩個(餘額 100 不夠付 250、8,000)、我的個人私帳一個銀行存款帳戶和一個現金錢包，還有一張個人信用卡。
    private func accountsForReimbursement() -> InMemoryAccountRepository {
        InMemoryAccountRepository(accounts: [
            .bank(BankAccount(id: AccountID("small-fund"), name: "零用公基金", colorHex: "#A8D8EA", balance: Money(100), isJointFund: true)),
            .bank(BankAccount(id: AccountID("fund"), name: "家庭共同基金", colorHex: "#A8D8EA", balance: Money(8000), isJointFund: true)),
            .bank(SampleAccounts.savings),
            .cash(SampleAccounts.wallet),
            .creditCard(SampleAccounts.card),
        ], summary: .zero)
    }

    @Test("撥款報銷的預設值：金額是待報銷總額、撥款帳戶是第一個餘額夠的共同基金、收款帳戶是我的個人帳戶")
    func reimbursementDefaults() async {
        let model = await loaded(.sample(advances: [InMemoryHouseholdRepository.myPendingAdvance]), accounts: accountsForReimbursement())
        let reimbursement = model.makeReimbursement(for: InMemoryHouseholdRepository.myPendingAdvance)

        await reimbursement.load()

        #expect(reimbursement.fundAccounts.map(\.name) == ["零用公基金", "家庭共同基金"])
        #expect(reimbursement.receivingAccounts.map(\.name) == ["iOS 測試存款", "iOS 測試皮夾"])
        #expect(reimbursement.fromAccountID == AccountID("fund"))
        #expect(reimbursement.toAccountID == SampleAccounts.savings.id)
        #expect(reimbursement.amountText == "250")
        #expect(reimbursement.note == "家庭基金撥款報銷 小明 代墊公帳")
        #expect(reimbursement.date == today)
    }

    @Test("撥款報銷：送出後回傳後端的訊息、資料版本遞增;金額不是正整數時不送出")
    func submitsReimbursement() async {
        let repository = InMemoryHouseholdRepository.sample(advances: [InMemoryHouseholdRepository.myPendingAdvance])
        let model = await loaded(repository, accounts: accountsForReimbursement())
        let reimbursement = model.makeReimbursement(for: InMemoryHouseholdRepository.myPendingAdvance)
        await reimbursement.load()

        reimbursement.amountText = "0"
        #expect(await reimbursement.submit() == nil)
        #expect(reimbursement.errorMessage == "請選擇撥款公帳、收款帳戶並輸入大於 0 的金額")

        reimbursement.amountText = "250"
        let message = await reimbursement.submit()

        #expect(message == "成功從共同基金撥款報銷 NT$ 250 給 小明！")
        #expect(await repository.reimbursements == [Reimbursement(
            memberID: me, fromAccountID: AccountID("fund"), toAccountID: SampleAccounts.savings.id, amount: Money(250),
            date: today, note: "家庭基金撥款報銷 小明 代墊公帳"
        )])
        #expect(dataVersion.value == 1)
    }

    @Test("還沒加入家庭群組")
    func withoutHousehold() async {
        let model = await loaded(InMemoryHouseholdRepository(household: nil))

        #expect(model.phase == .loaded)
        #expect(model.household == nil)
    }

    @Test("建立家庭群組：名稱必填")
    func createRequiresName() async {
        let repository = InMemoryHouseholdRepository(household: nil)
        let model = await loaded(repository)

        model.createName = "   "
        #expect(!model.canCreate)
        await model.create()

        #expect(await repository.createdNames.isEmpty)
    }

    @Test("建立成功後資料版本遞增，並顯示新的家庭群組(我是管理員)")
    func create() async throws {
        let repository = InMemoryHouseholdRepository(household: nil)
        let model = await loaded(repository)
        model.createName = " 我們家 "

        await model.create()

        #expect(await repository.createdNames == ["我們家"])
        #expect(dataVersion.value == 1)
        let household = try #require(model.household)
        #expect(household.name == "我們家")
        #expect(household.myRole == .admin)
    }

    @Test("用邀請碼加入：錯誤時顯示後端的訊息")
    func joinFailure() async {
        let repository = InMemoryHouseholdRepository(household: nil)
        await repository.fail(with: .rejected("邀請碼無效或已過期"))
        let model = HouseholdModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(), dataVersion: dataVersion, currentUserID: me
        )
        model.joinCode = "FAM-0000"

        await model.join()

        #expect(model.alertMessage == "邀請碼無效或已過期")
        #expect(dataVersion.value == 0)
    }

    @Test("用邀請碼加入成功後資料版本遞增;邀請碼必填")
    func join() async {
        let repository = InMemoryHouseholdRepository(household: nil)
        let model = await loaded(repository)

        model.joinCode = " "
        #expect(!model.canJoin)

        model.joinCode = " fam-ab12 "
        await model.join()

        #expect(await repository.joinedCodes == ["fam-ab12"])
        #expect(dataVersion.value == 1)
    }

    @Test("我的角色與成員人數")
    func summary() async throws {
        let model = await loaded(InMemoryHouseholdRepository.sample())
        let household = try #require(model.household)

        #expect(household.myRole.title == "管理員")
        #expect(HouseholdRole.member.title == "一般成員")
        #expect(model.memberCountText == "2 位成員")
    }

    @Test("每按一次邀請，就產生一組新的邀請碼")
    func inviteEveryTime() async throws {
        let repository = InMemoryHouseholdRepository.sample()
        let model = await loaded(repository)

        await model.invite()
        let first = try #require(model.invitation)
        await model.invite()
        let second = try #require(model.invitation)

        #expect(first.code != second.code)
        #expect(await repository.inviteCount == 2)
    }

    @Test("只有管理員看得到「移除」,而且只出現在一般成員上")
    func canRemove() async throws {
        let adminView = await loaded(InMemoryHouseholdRepository.sample())
        let members = try #require(adminView.household?.members)

        #expect(members.map { adminView.canRemove($0) } == [false, true])

        let memberView = await loaded(InMemoryHouseholdRepository.sample(myRole: .member))
        #expect(memberView.household?.members.contains { memberView.canRemove($0) } == false)
    }

    @Test("邀請還沒回來之前再按一次，不會多產生一組邀請碼", .timeLimit(.minutes(1)))
    func inviteIgnoresRepeatedTaps() async throws {
        let gate = Gate()
        let repository = InMemoryHouseholdRepository.sample(gate: gate)
        let model = await loaded(repository)

        let first = Task { await model.invite() }
        await gate.waitUntilReached()
        #expect(model.isInviting)
        await model.invite()
        await gate.open()
        await first.value

        #expect(await repository.inviteCount == 1)
        #expect(!model.isInviting)
    }

    @Test("移除與離開的確認文字")
    func confirmations() async {
        let model = await loaded(InMemoryHouseholdRepository.sample())

        #expect(model.removeConfirmation(for: member("小美", .member)) == "確定要將「小美」移出家庭群組嗎？")
        #expect(model.leaveConfirmation == "確定要退出這個家庭群組嗎？退出後將無法查看這個家庭群組的家庭公帳。")
    }

    @Test("移除成員後資料版本遞增")
    func remove() async throws {
        let repository = InMemoryHouseholdRepository.sample()
        let model = await loaded(repository)
        let mei = try #require(model.household?.members.last)

        await model.remove(mei)

        #expect(await repository.removedIDs == [mei.userID])
        #expect(dataVersion.value == 1)
        #expect(model.household?.members.count == 1)
    }

    @Test("離開後資料版本遞增，回到還沒加入的畫面")
    func leave() async {
        let repository = InMemoryHouseholdRepository.sample()
        let model = await loaded(repository)

        await model.leave()

        #expect(await repository.leaveCount == 1)
        #expect(dataVersion.value == 1)
        #expect(model.household == nil)
    }

    @Test("名稱開頭字", arguments: [("小美", "小"), ("alice", "A"), ("", "?")])
    func initial(name: String, expected: String) {
        #expect(member(name, .member).initial == expected)
    }

    /// web 直接取 UTC 字串的前 10 個字，台灣時間早上會顯示成前一天(parity 刻意偏離第 29 項)。
    @Test("加入日期換成當地的日期")
    func joinedDate() throws {
        let taipei = try #require(TimeZone(identifier: "Asia/Taipei"))

        #expect(member("小美", .member).joinedDateText(in: taipei) == "2026/09/28")
    }
}
