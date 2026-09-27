/// 資金帳戶(`/accounts`)。範圍是整個家庭群組：包含家庭成員的資金帳戶。
public protocol AccountRepository: Sendable {
    /// 所有資金帳戶，順序照後端(建立時間由舊到新)。
    func accounts() async throws -> [Account]

    /// 家庭群組的資金指標。
    func balanceSummary() async throws -> BalanceSummary
}
