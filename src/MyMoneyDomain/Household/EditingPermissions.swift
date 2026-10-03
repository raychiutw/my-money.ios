/// 誰能改什麼(上游 ADR 0013、#133):以登入的人與他在家庭裡的角色，決定帳戶、信用卡、交易的編輯與刪除入口要不要顯示。
///
/// 後端是最後一道防線(403);這裡只決定畫面上要不要給入口，跟 web 的 `canModifyAccount`、`canOperateCard`、`canModifyTx` 一樣。
/// 不知道登入的是誰、或資料沒有擁有者時不擅自擋，交給後端判斷。系統紀錄不能編輯另有規則(`Transaction.isSystemRecord`)，不在這裡。
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
        account.isJointFund ? (isMine(account.ownerID) || isAdmin) : isMine(account.ownerID)
    }

    /// 信用卡的還款沖銷、出帳作業、校準:個人信用卡只有持卡人;家庭信用卡全員都可以。
    public func canOperate(_ card: CreditCard) -> Bool {
        card.isJointFund || isMine(card.ownerID)
    }

    /// 這張卡在畫面上要脫敏(上游 ADR 0015):後端標了 `is_masked`，或是擁有者明確不是我的個人卡。
    /// 家庭卡不脫敏;不知道登入的是誰、或資料沒有擁有者時不擅自遮蔽。
    public func isMasked(_ card: CreditCard) -> Bool {
        card.isMasked || (!card.isJointFund && !isMine(card.ownerID))
    }

    /// 交易的編輯與刪除:個人私帳只有記錄者，家庭管理員也不行;家庭公帳是記錄者或家庭管理員。
    public func canModify(_ transaction: Transaction) -> Bool {
        transaction.isShared ? (isMine(transaction.recorderID) || isAdmin) : isMine(transaction.recorderID)
    }
}
