/// 資金帳戶(`/accounts`)。範圍是整個家庭群組：包含家庭成員的資金帳戶。
public protocol AccountRepository: Sendable {
    /// 所有資金帳戶，順序照後端(建立時間由舊到新)。
    func accounts() async throws -> [Account]

    /// 家庭群組的資金指標。
    func balanceSummary() async throws -> BalanceSummary

    func create(_ draft: AccountDraft) async throws

    /// 編輯時不能改類型:`draft` 的類型必須跟原本的資金帳戶一樣。
    func update(_ id: AccountID, with draft: AccountDraft) async throws

    /// 刪除資金帳戶。這個帳戶的交易紀錄會被後端一併刪除。
    func delete(_ id: AccountID) async throws
}
