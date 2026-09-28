/// 資金帳戶(`/accounts`)。
///
/// 帳戶檢視範圍用 `ViewScope`:全部是「本人全部 + 其他成員的家庭公用」,家庭公用是全體成員的家庭公用帳戶，
/// 個人私帳是本人的個人私帳。其他成員的個人私帳一律看不到(後端 `bd0507b`)。
public protocol AccountRepository: Sendable {
    /// 這個範圍的資金帳戶，順序照後端(建立時間由舊到新)。
    func accounts(scope: ViewScope) async throws -> [Account]

    /// 這個範圍的資金指標。
    func balanceSummary(scope: ViewScope) async throws -> BalanceSummary

    func create(_ draft: AccountDraft) async throws

    /// 編輯時不能改類型:`draft` 的類型必須跟原本的資金帳戶一樣。
    func update(_ id: AccountID, with draft: AccountDraft) async throws

    /// 刪除資金帳戶。這個帳戶的交易紀錄會被後端一併刪除。
    func delete(_ id: AccountID) async throws

    /// 信用卡還款沖銷。
    func payCreditCard(_ payment: CardPayment) async throws

    /// 結帳日出帳結轉：把未出帳金額一次移到已出帳待繳金額。回傳後端的訊息。
    func rollOverStatement(_ id: AccountID) async throws -> String
}

extension AccountRepository {
    /// 全部範圍(本人全部 + 家庭公用),給只需要選帳戶的畫面用，例如記一筆、固定收支。
    public func accounts() async throws -> [Account] {
        try await accounts(scope: .all)
    }

    public func balanceSummary() async throws -> BalanceSummary {
        try await balanceSummary(scope: .all)
    }
}
