/// 帳戶檢視範圍(CONTEXT.md):全部是「本人全部 + 其他成員歸屬家庭共同基金的帳戶」,家庭共同基金是全體成員歸屬家庭共同基金的帳戶，
/// 個人私帳是本人的個人私帳。其他成員的個人私帳一律看不到(後端 `bd0507b`)。跟交易紀錄的視角(`ViewScope`)是兩件事。
public enum AccountScope: String, Sendable, CaseIterable {
    case all
    case household
    case personal
}

/// 資產帳戶(`/accounts`)。
public protocol AccountRepository: Sendable {
    /// 這個範圍的資產帳戶，順序照後端(建立時間由舊到新)。
    func accounts(scope: AccountScope) async throws -> [Account]

    /// 這個範圍的資金指標。
    func balanceSummary(scope: AccountScope) async throws -> BalanceSummary

    func create(_ draft: AccountDraft) async throws

    /// 編輯時不能改類型:`draft` 的類型必須跟原本的資產帳戶一樣。
    func update(_ id: AccountID, with draft: AccountDraft) async throws

    /// 刪除資產帳戶。這個帳戶的交易紀錄會被後端一併刪除。
    func delete(_ id: AccountID) async throws

    /// 信用卡扣款還款。
    func payCreditCard(_ payment: CardPayment) async throws

    /// 結帳日出帳作業：把未出帳款一次轉入已出帳待繳款，後端並記錄這次出帳作業的時間點(`da82a11` 起)。回傳後端的訊息。
    func rollOverStatement(_ id: AccountID) async throws -> String

    /// 信用卡未出帳自動校準(後端 `b5cbe09`,`da82a11` 改了算法):把未出帳款覆寫成上一次結帳日出帳作業之後的消費合計，
    /// 扣掉同一段期間的刷退和還款。回傳後端的訊息。
    func reconcileUnbilled(_ id: AccountID) async throws -> String

    /// ATM 提款／帳戶互轉。回傳後端的訊息。
    func transfer(_ transfer: AccountTransfer) async throws -> String
}

extension AccountRepository {
    /// 全部範圍(本人全部 + 家庭共同基金),給只需要選帳戶的畫面用，例如記一筆、週期收支。
    public func accounts() async throws -> [Account] {
        try await accounts(scope: .all)
    }

    public func balanceSummary() async throws -> BalanceSummary {
        try await balanceSummary(scope: .all)
    }
}
