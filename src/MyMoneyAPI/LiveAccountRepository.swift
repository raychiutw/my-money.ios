import Foundation
import MyMoneyDomain

/// `/accounts` 的 URLSession 實作。
public struct LiveAccountRepository: AccountRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func accounts() async throws -> [Account] {
        let dtos: [AccountDTO] = try await client.get("/accounts")
        return try dtos.map { try $0.account() }
    }

    public func balanceSummary() async throws -> BalanceSummary {
        let dto: BalanceSummaryDTO = try await client.get("/accounts/balance")
        return dto.summary
    }
}

/// `GET /accounts` 的一筆:資料表欄位，所以是 snake_case。
///
/// `balance` 一詞兩義：銀行存款帳戶是餘額，信用卡帳戶是已出帳待繳金額(CLAUDE.md「規則」)。
private struct AccountDTO: Decodable {
    let id: String
    let name: String
    let type: String
    let balance: Decimal
    let unbilled: Decimal?
    let creditLimit: Decimal?
    let statementDay: Int?
    let paymentDueDay: Int?
    let color: String
    /// 0/1;`79edd20` 以前的資料可能沒有這個欄位。
    let isJoint: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, balance, unbilled, color
        case creditLimit = "credit_limit"
        case statementDay = "statement_day"
        case paymentDueDay = "payment_due_day"
        case isJoint = "is_joint"
    }

    func account() throws -> Account {
        switch type {
        case "bank":
            return .bank(BankAccount(
                id: AccountID(id),
                name: name,
                colorHex: color,
                balance: Money(balance),
                isJointFund: isJoint == 1
            ))
        case "credit_card":
            return .creditCard(CreditCard(
                id: AccountID(id),
                name: name,
                colorHex: color,
                billedDebt: Money(balance),
                unbilledDebt: Money(unbilled ?? 0),
                creditLimit: creditLimit.map(Money.init),
                statementDay: statementDay,
                paymentDueDay: paymentDueDay
            ))
        default:
            throw RepositoryError.unreadableResponse
        }
    }
}

/// `GET /accounts/balance`:計算出來的指標，所以是 camelCase。
private struct BalanceSummaryDTO: Decodable {
    let bankTotal: Decimal
    let ccBilled: Decimal
    let ccUnbilled: Decimal
    let available: Decimal
    let monthlyFixed: Decimal
    let monthlyGoals: Decimal
    let disposable: Decimal

    var summary: BalanceSummary {
        BalanceSummary(
            bankBalanceTotal: Money(bankTotal),
            billedDebtTotal: Money(ccBilled),
            unbilledDebtTotal: Money(ccUnbilled),
            availableBalance: Money(available),
            monthlyAmortization: Money(monthlyFixed),
            monthlySavingsReserve: Money(monthlyGoals),
            disposableCash: Money(disposable)
        )
    }
}
