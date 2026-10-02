import MyMoneyDomain
import Testing

/// 誰能改哪個帳戶、哪筆交易、哪張卡(上游 ADR 0013、#133)。後端是最後一道(403),這裡決定要不要顯示入口。
@Suite("編輯權限")
struct EditingPermissionsTests {
    private let me = UserID("me")
    private let other = UserID("other")

    private func permissions(_ role: HouseholdRole?, user: UserID? = UserID("me")) -> EditingPermissions {
        EditingPermissions(userID: user, role: role)
    }

    private func bank(owner: UserID?, joint: Bool) -> Account {
        .bank(BankAccount(id: AccountID("a"), name: "帳戶", colorHex: "#A8D8EA", balance: Money(1), isJointFund: joint, ownerID: owner))
    }

    private func card(owner: UserID?, joint: Bool) -> CreditCard {
        CreditCard(
            id: AccountID("c"), name: "卡", colorHex: "#FFD4A0", billedDebt: Money(1), unbilledDebt: Money(1), creditLimit: nil,
            statementDay: nil, paymentDueDay: nil, isJointFund: joint, ownerID: owner
        )
    }

    private func transaction(recorder: UserID?, shared: Bool, category: TransactionCategory = .dining) -> Transaction {
        Transaction(
            id: TransactionID("t"), accountID: AccountID("a"), accountName: "帳戶", type: .expense, category: category, amount: Money(1),
            note: "", date: CalendarDay(year: 2026, month: 10, day: 2), isShared: shared, recorderName: nil, recorderID: recorder
        )
    }

    @Test("帳戶:個人私帳只有本人能編輯、刪除，家庭管理員也不行")
    func privateAccountIsOwnerOnly() {
        for role: HouseholdRole? in [nil, .admin, .member] {
            #expect(permissions(role).canModify(bank(owner: me, joint: false)))
            #expect(!permissions(role).canModify(bank(owner: other, joint: false)), "角色 \(String(describing: role))")
        }
    }

    @Test("帳戶:家庭共同帳戶是建立者或家庭管理員，其他一般成員不行")
    func jointAccountIsCreatorOrAdmin() {
        #expect(permissions(.member).canModify(bank(owner: me, joint: true)), "建立者是一般成員")
        #expect(permissions(.admin).canModify(bank(owner: me, joint: true)))
        #expect(permissions(.admin).canModify(bank(owner: other, joint: true)), "家庭管理員可以改別人建立的共同帳戶")
        #expect(!permissions(.member).canModify(bank(owner: other, joint: true)))
    }

    @Test("信用卡的還款沖銷、出帳作業、校準:個人信用卡只有持卡人，家庭信用卡全員都可以")
    func cardOperation() {
        for role: HouseholdRole? in [nil, .admin, .member] {
            #expect(permissions(role).canOperate(card(owner: me, joint: false)))
            #expect(!permissions(role).canOperate(card(owner: other, joint: false)), "個人卡連家庭管理員也不行")
            #expect(permissions(role).canOperate(card(owner: other, joint: true)))
        }
    }

    @Test("信用卡的編輯與刪除跟帳戶一樣:家庭信用卡只有建立者或家庭管理員")
    func cardIsAnAccountForModification() {
        #expect(permissions(.member).canModify(.creditCard(card(owner: me, joint: true))))
        #expect(permissions(.admin).canModify(.creditCard(card(owner: other, joint: true))))
        #expect(!permissions(.member).canModify(.creditCard(card(owner: other, joint: true))))
        #expect(!permissions(.admin).canModify(.creditCard(card(owner: other, joint: false))))
    }

    @Test("交易:個人私帳只有記錄者，家庭管理員也不行")
    func privateTransactionIsRecorderOnly() {
        for role: HouseholdRole? in [nil, .admin, .member] {
            #expect(permissions(role).canModify(transaction(recorder: me, shared: false)))
            #expect(!permissions(role).canModify(transaction(recorder: other, shared: false)), "角色 \(String(describing: role))")
        }
    }

    @Test("交易:家庭公帳是記錄者或家庭管理員，其他一般成員不行")
    func sharedTransactionIsRecorderOrAdmin() {
        #expect(permissions(.member).canModify(transaction(recorder: me, shared: true)))
        #expect(permissions(.admin).canModify(transaction(recorder: other, shared: true)))
        #expect(!permissions(.member).canModify(transaction(recorder: other, shared: true)))
        #expect(!permissions(nil).canModify(transaction(recorder: other, shared: true)), "沒有家庭時不可能是管理員")
    }

    @Test("不知道登入的是誰、或資料沒有擁有者時，不擅自擋(後端仍會判斷，跟 web 一樣)")
    func unknownIsPermissive() {
        #expect(permissions(.member, user: nil).canModify(bank(owner: other, joint: false)))
        #expect(permissions(.member, user: nil).canModify(transaction(recorder: other, shared: true)))
        #expect(permissions(.member).canModify(bank(owner: nil, joint: false)))
        #expect(permissions(.member).canModify(transaction(recorder: nil, shared: false)))
        #expect(permissions(.member).canOperate(card(owner: nil, joint: false)))
    }
}
