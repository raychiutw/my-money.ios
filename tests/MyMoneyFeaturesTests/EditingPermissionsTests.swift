import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 帳戶、交易、信用卡的編輯與刪除權限防呆(上游 ADR 0013、#133):畫面 model 只在有權限時給入口，後端的 403 照原文顯示。
@MainActor
@Suite("編輯權限防呆")
struct EditingPermissionsFeatureTests {
    private let me = UserID("me")
    private let mei = UserID("sample-mei")
    private let today = CalendarDay(year: 2026, month: 10, day: 2)

    private func permissions(_ role: HouseholdRole?, user: UserID? = UserID("me")) -> PermissionsModel {
        PermissionsModel(userID: user, role: role)
    }

    private func bank(_ id: String, owner: UserID, joint: Bool) -> BankAccount {
        BankAccount(id: AccountID(id), name: id, colorHex: "#A8D8EA", balance: Money(100), isJointFund: joint, ownerID: owner)
    }

    private func card(_ id: String, owner: UserID, joint: Bool) -> CreditCard {
        CreditCard(
            id: AccountID(id), name: id, colorHex: "#FFD4A0", billedDebt: Money(1000), unbilledDebt: Money(500), creditLimit: nil,
            statementDay: nil, paymentDueDay: nil, isJointFund: joint, ownerID: owner
        )
    }

    private func accountsModel(_ role: HouseholdRole?, accounts: [Account]) async -> (AccountsModel, InMemoryAccountRepository) {
        let repository = InMemoryAccountRepository(accounts: accounts, summary: SampleAccounts.summary)
        let model = AccountsModel(repository: repository, dataVersion: DataVersion(), permissions: permissions(role))
        await model.load()
        return (model, repository)
    }

    @Test("帳戶:一般成員改不了別人的家庭共同帳戶與個人私帳，自己的可以;家庭管理員改得了共同帳戶，但改不了別人的私帳")
    func accountModification() async {
        let mineJoint = Account.bank(bank("mine-joint", owner: me, joint: true))
        let meiJoint = Account.bank(bank("mei-joint", owner: mei, joint: true))
        let meiPrivate = Account.bank(bank("mei-private", owner: mei, joint: false))
        let accounts = [mineJoint, meiJoint, meiPrivate]

        let (member, _) = await accountsModel(.member, accounts: accounts)
        #expect([mineJoint, meiJoint, meiPrivate].map(member.canModify) == [true, false, false])

        let (admin, _) = await accountsModel(.admin, accounts: accounts)
        #expect([mineJoint, meiJoint, meiPrivate].map(admin.canModify) == [true, true, false])
    }

    @Test("沒有設定權限時(例如還沒登入的預覽)不擋，交給後端")
    func withoutPermissionsNothingIsHidden() async {
        let model = AccountsModel(
            repository: InMemoryAccountRepository(accounts: [.bank(bank("x", owner: mei, joint: false))], summary: SampleAccounts.summary),
            dataVersion: DataVersion()
        )
        #expect(model.canModify(.bank(bank("x", owner: mei, joint: false))))
        #expect(model.canOperate(card("c", owner: mei, joint: false)))
    }

    @Test("沒有權限就不會送出刪除，也不會遞增資料版本")
    func deleteIsGuarded() async {
        let meiJoint = Account.bank(bank("mei-joint", owner: mei, joint: true))
        let (member, repository) = await accountsModel(.member, accounts: [meiJoint])

        await member.delete(meiJoint)

        #expect(await repository.deletedIDs.isEmpty)

        let (admin, adminRepository) = await accountsModel(.admin, accounts: [meiJoint])
        await admin.delete(meiJoint)
        #expect(await adminRepository.deletedIDs == [meiJoint.id])
    }

    @Test("信用卡:個人信用卡只有持卡人能還款沖銷、出帳、校準;家庭信用卡全員都可以")
    func cardOperation() async {
        let (member, _) = await accountsModel(.member, accounts: [])
        #expect(member.canOperate(card("mine", owner: me, joint: false)))
        #expect(!member.canOperate(card("mei-private", owner: mei, joint: false)))
        #expect(member.canOperate(card("mei-joint", owner: mei, joint: true)))

        let (admin, _) = await accountsModel(.admin, accounts: [])
        #expect(!admin.canOperate(card("mei-private", owner: mei, joint: false)), "家庭管理員也不能動別人的個人信用卡")
    }

    @Test("信用卡詳細頁:跟帳戶頁用同一份權限，沒有權限就沒有編輯、繳款、出帳、校準")
    func cardDetailFollowsPermissions() async {
        let meiJoint = card("mei-joint", owner: mei, joint: true)
        let repository = InMemoryAccountRepository(accounts: [.creditCard(meiJoint)], summary: SampleAccounts.summary)

        let member = AccountsModel(repository: repository, dataVersion: DataVersion(), permissions: permissions(.member))
        await member.load()
        let memberDetail = member.makeCardDetail(for: meiJoint)
        #expect(!memberDetail.canEdit, "家庭信用卡只有建立者或家庭管理員能編輯")
        #expect(memberDetail.canOperate, "家庭信用卡全員都可以還款、出帳、校準")

        let admin = AccountsModel(repository: repository, dataVersion: DataVersion(), permissions: permissions(.admin))
        await admin.load()
        #expect(admin.makeCardDetail(for: meiJoint).canEdit)

        let meiPrivate = card("mei-private", owner: mei, joint: false)
        let privateDetail = member.makeCardDetail(for: meiPrivate)
        #expect(!privateDetail.canOperate && !privateDetail.canEdit)
        #expect(privateDetail.paymentPresets.isEmpty || !privateDetail.canOperate)
    }

    // MARK: 交易

    private func transaction(_ id: String, recorder: UserID, shared: Bool, category: TransactionCategory = .dining) -> Transaction {
        Transaction(
            id: TransactionID(id), accountID: SampleAccounts.savings.id, accountName: SampleAccounts.savings.name, type: .expense,
            category: category, amount: Money(120), note: "", date: today, isShared: shared, recorderName: recorder == me ? "小明" : "小美",
            recorderID: recorder
        )
    }

    private func transactionsModel(_ role: HouseholdRole?, _ transactions: [Transaction]) async -> (TransactionsModel, InMemoryTransactionRepository) {
        let repository = InMemoryTransactionRepository(transactions: transactions)
        let model = TransactionsModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(), dataVersion: DataVersion(), currentUser: me,
            permissions: permissions(role), today: { today }
        )
        await model.load()
        return (model, repository)
    }

    @Test("交易:個人私帳只有記錄者;家庭公帳是記錄者或家庭管理員;系統紀錄一律不行(取交集)")
    func transactionModification() async {
        let mineShared = transaction("mine-shared", recorder: me, shared: true)
        let meiShared = transaction("mei-shared", recorder: mei, shared: true)
        let meiPrivate = transaction("mei-private", recorder: mei, shared: false)
        let mineSystem = transaction("mine-system", recorder: me, shared: true, category: .creditCardRepayment)
        let all = [mineShared, meiShared, meiPrivate, mineSystem]

        let (member, _) = await transactionsModel(.member, all)
        #expect(all.map(member.canModify) == [true, false, false, false])

        let (admin, _) = await transactionsModel(.admin, all)
        #expect(all.map(admin.canModify) == [true, true, false, false], "家庭管理員改得了別人的公帳，改不了別人的私帳，也改不了系統紀錄")
    }

    @Test("沒有權限的交易不會打開編輯器，也不會送出刪除")
    func transactionGuards() async {
        let meiShared = transaction("mei-shared", recorder: mei, shared: true)
        let (member, repository) = await transactionsModel(.member, [meiShared])

        #expect(member.makeEditor(for: meiShared) == nil)
        await member.delete(meiShared)
        #expect(await repository.deletedIDs.isEmpty)

        let (admin, adminRepository) = await transactionsModel(.admin, [meiShared])
        #expect(admin.makeEditor(for: meiShared) != nil)
        await admin.delete(meiShared)
        #expect(await adminRepository.deletedIDs == [meiShared.id])
    }

    @Test("鎖定標記的說明:系統紀錄與沒有權限各有各的說法;可以改的沒有說明")
    func lockReasons() async {
        let mineShared = transaction("mine-shared", recorder: me, shared: true)
        let meiShared = transaction("mei-shared", recorder: mei, shared: true)
        let meiPrivate = transaction("mei-private", recorder: mei, shared: false)
        let mineSystem = transaction("mine-system", recorder: me, shared: true, category: .creditCardRepayment)
        let (member, _) = await transactionsModel(.member, [mineShared, meiShared, meiPrivate, mineSystem])

        #expect(member.lockReason(for: mineShared) == nil)
        #expect(member.lockReason(for: mineSystem) == "系統紀錄，不能編輯或刪除")
        #expect(member.lockReason(for: meiShared) == "他人記錄的公帳，僅記錄者或家庭管理員可以編輯、刪除")
        #expect(member.lockReason(for: meiPrivate) == "他人的私帳，僅記錄者本人可以編輯、刪除")
    }

    // MARK: 權限本身

    @Test("角色第一次需要時向後端問;沒有家庭是沒有角色;家庭頁載入之後同步")
    func roleLoading() async {
        let model = PermissionsModel(userID: me, households: InMemoryHouseholdRepository.sample(myRole: .member))
        #expect(model.current.role == nil)

        await model.loadIfNeeded()
        #expect(model.current.role == .member)

        model.update(role: .admin)
        #expect(model.current.role == .admin)

        let none = PermissionsModel(userID: me, households: InMemoryHouseholdRepository(household: nil))
        await none.loadIfNeeded()
        #expect(none.current.role == nil)
    }

    @Test("取得角色失敗時不當成沒有家庭，下一次還會再問")
    func roleLoadingFailureRetries() async {
        let repository = InMemoryHouseholdRepository.sample(myRole: .admin)
        await repository.fail(with: .rejected("伺服器忙碌"))
        let model = PermissionsModel(userID: me, households: repository)

        await model.loadIfNeeded()
        #expect(model.current.role == nil)

        await repository.clearFailure()
        await model.loadIfNeeded()
        #expect(model.current.role == .admin)
    }

    @Test("角色取得失敗之後，帳戶頁、交易頁下一次載入會再問一次")
    func pagesRetryTheRole() async {
        let households = InMemoryHouseholdRepository.sample(myRole: .admin)
        await households.fail(with: .rejected("伺服器忙碌"))
        let permissions = PermissionsModel(userID: me, households: households)
        let accounts = AccountsModel(
            repository: InMemoryAccountRepository.sample(), dataVersion: DataVersion(), permissions: permissions
        )

        await accounts.load()
        #expect(permissions.current.role == nil)

        await households.clearFailure()
        await accounts.load()
        #expect(permissions.current.role == .admin)

        let transactionsPermissions = PermissionsModel(userID: me, households: InMemoryHouseholdRepository.sample(myRole: .member))
        let transactions = TransactionsModel(
            repository: InMemoryTransactionRepository(transactions: []), dataVersion: DataVersion(), currentUser: me,
            permissions: transactionsPermissions, today: { today }
        )
        await transactions.load()
        #expect(transactionsPermissions.current.role == .member)
    }

    @Test("家庭頁載入、建立家庭之後，權限跟著家庭的角色更新")
    func householdModelKeepsPermissionsInSync() async {
        let permissions = PermissionsModel(userID: me, role: nil)
        let repository = InMemoryHouseholdRepository(household: nil)
        let model = HouseholdModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(), permissions: permissions, dataVersion: DataVersion()
        )
        await model.load()
        #expect(permissions.current.role == nil)

        model.createName = "我們家"
        await model.create()
        #expect(permissions.current.role == .admin)

        await model.leave()
        #expect(permissions.current.role == nil)
    }
}
