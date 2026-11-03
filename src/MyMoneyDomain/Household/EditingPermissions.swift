/// 誰能改什麼(上游 ADR 0013、#133):以登入的人與他在家庭裡的角色，決定帳戶、信用卡、交易的編輯與刪除入口要不要顯示。
///
/// 後端是最後一道防線(403);這裡只決定畫面上要不要給入口，跟 web 的 `canModifyAccount`、`canOperateCard`、`canModifyTx` 一樣。
/// 不知道登入的是誰、或資料沒有擁有者時不擅自擋，交給後端判斷。成對系統紀錄(`Transaction.isSystemRecord`,上游 ADR 0031)的權限規則見 `canModify(_ transaction:)`。
public struct EditingPermissions: Hashable, Sendable {
    /// 登入的人;不知道時是 `nil`。
    public let userID: UserID?
    /// 登入的人在家庭裡的角色;沒有家庭(或還不知道)時是 `nil`。
    public let role: HouseholdRole?

    public init(userID: UserID?, role: HouseholdRole?) {
        self.userID = userID
        self.role = role
    }

    private var isAdmin: Bool { role == .admin }

    /// 擁有者(或記錄者)是不是我;任一邊不知道時算是我，交給後端判斷。
    private func isMine(_ ownerID: UserID?) -> Bool {
        userID == nil || ownerID == nil || ownerID == userID
    }

    /// 帳戶(含信用卡)的編輯與刪除:個人私帳只有本人，家庭管理員也不行;家庭共同帳戶是建立者或家庭管理員。
    public func canModify(_ account: Account) -> Bool {
        // 後端標了脫敏的卡一定是他人的個人卡(即使沒回擁有者)，不能改。
        if case .creditCard(let card) = account, card.isMasked { return false }
        return account.isJointFund ? (isMine(account.ownerID) || isAdmin) : isMine(account.ownerID)
    }

    /// 能不能當信用卡的預設扣款帳戶(上游 `b06d17c`、#156):活存帳戶必須是本人的或家庭共同帳戶,否則後端回 400;管理員也不能綁他人的私人帳戶。
    public func canUseAsPaymentAccount(_ bank: BankAccount) -> Bool {
        bank.isJointFund || isMine(bank.ownerID)
    }

    /// 信用卡的還款沖銷、出帳作業、校準:個人信用卡只有持卡人;家庭信用卡全員都可以。
    public func canOperate(_ card: CreditCard) -> Bool {
        !card.isMasked && (card.isJointFund || isMine(card.ownerID))
    }

    /// 這張卡在畫面上要脫敏(上游 ADR 0015):後端標了 `is_masked`，或是擁有者明確不是我的個人卡。
    /// 家庭卡不脫敏;不知道登入的是誰、或資料沒有擁有者時不擅自遮蔽。
    public func isMasked(_ card: CreditCard) -> Bool {
        card.isMasked || (!card.isJointFund && !isMine(card.ownerID))
    }

    /// 週期收支的編輯與刪除(上游 ADR 0016):個人私帳只有建立者本人，家庭管理員也不行;家庭公帳是建立者或家庭管理員。
    public func canModify(_ item: RecurringItem) -> Bool {
        item.isShared ? (isMine(item.ownerID) || isAdmin) : isMine(item.ownerID)
    }

    /// 交易的編輯與刪除:個人私帳只有記錄者，家庭管理員也不行;家庭公帳是記錄者或家庭管理員。
    /// 成對系統紀錄(上游 ADR 0031):內部轉帳、ATM 提款、信用卡還款是記錄者或家庭管理員;公帳代墊報銷限家庭管理員或被報銷成員,
    /// 另一端是誰 client 不知道,所以放行、交給後端判斷(403 的訊息照顯示)。
    public func canModify(_ transaction: Transaction) -> Bool {
        if transaction.isSystemRecord {
            return transaction.category == .advanceReimbursement || isMine(transaction.recorderID) || isAdmin
        }
        return transaction.isShared ? (isMine(transaction.recorderID) || isAdmin) : isMine(transaction.recorderID)
    }
}
