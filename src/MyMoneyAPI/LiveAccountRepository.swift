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

    public func create(_ draft: AccountDraft) async throws {
        try await client.send("POST", "/accounts", body: AccountBody(draft))
    }

    public func update(_ id: AccountID, with draft: AccountDraft) async throws {
        try await client.send("PUT", "/accounts/\(id.rawValue)", body: AccountBody(draft))
    }

    public func delete(_ id: AccountID) async throws {
        try await client.send("DELETE", "/accounts/\(id.rawValue)")
    }
}

/// `POST` 與 `PUT /accounts` 的 body。
///
/// 銀行存款帳戶不送信用額度與日期(`nil` 不會被編碼);`is_joint` 一定要送，
/// 因為後端的 PUT 沒收到時會寫成 0,把家庭共同基金的標記清掉。
private struct AccountBody: Encodable {
    let type: String
    let name: String
    let balance: Decimal
    let unbilled: Decimal
    let creditLimit: Decimal?
    let statementDay: Int?
    let paymentDueDay: Int?
    let color: String
    let isJoint: Int

    enum CodingKeys: String, CodingKey {
        case type, name, balance, unbilled, color
        case creditLimit = "credit_limit"
        case statementDay = "statement_day"
        case paymentDueDay = "payment_due_day"
        case isJoint = "is_joint"
    }

    init(_ draft: AccountDraft) {
        switch draft {
        case .bank(let bank):
            type = "bank"
            name = bank.name
            balance = bank.balance.amount
            unbilled = 0
            creditLimit = nil
            statementDay = nil
            paymentDueDay = nil
            color = bank.colorHex
            isJoint = bank.isJointFund ? 1 : 0
        case .creditCard(let card):
            type = "credit_card"
            name = card.name
            balance = card.billedDebt.amount
            unbilled = card.unbilledDebt.amount
            creditLimit = card.creditLimit?.amount
            statementDay = card.statementDay
            paymentDueDay = card.paymentDueDay
            color = card.colorHex
            isJoint = 0
        }
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
