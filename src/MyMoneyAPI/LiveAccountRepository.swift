import Foundation
import MyMoneyDomain

/// `/accounts` 的 URLSession 實作。
public struct LiveAccountRepository: AccountRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// 不認得的帳戶類型(後端將來新增的)只略過那一個，不讓整份清單失敗(parity 刻意偏離)。
    public func accounts(scope: AccountScope) async throws -> [Account] {
        let dtos: [AccountDTO] = try await client.get("/accounts", query: Self.query(scope))
        return dtos.compactMap { $0.account() }
    }

    public func balanceSummary(scope: AccountScope) async throws -> BalanceSummary {
        let dto: BalanceSummaryDTO = try await client.get("/accounts/balance", query: Self.query(scope))
        return dto.summary
    }

    /// 一律明確帶 `scope`,`all` 也帶，不依賴後端的預設範圍。
    private static func query(_ scope: AccountScope) -> [URLQueryItem] {
        [URLQueryItem(name: "scope", value: scope.rawValue)]
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

    public func payCreditCard(_ payment: CardPayment) async throws {
        try await client.send("POST", "/accounts/pay-credit-card", body: PaymentBody(payment))
    }

    public func rollOverStatement(_ id: AccountID) async throws -> String {
        let dto: MessageDTO = try await client.send("POST", "/accounts/\(id.rawValue)/rollover-statement")
        return dto.message
    }

    public func transfer(_ transfer: AccountTransfer) async throws -> String {
        let dto: MessageDTO = try await client.send("POST", "/accounts/transfer", body: TransferBody(transfer))
        return dto.message
    }
}

/// `POST /accounts/transfer` 的 body。回應的 `data` 是 `{message, from_balance, to_balance}`,只用 `message`。
private struct TransferBody: Encodable {
    let fromAccountID: String
    let toAccountID: String
    let amount: Decimal
    let date: String
    let note: String

    enum CodingKeys: String, CodingKey {
        case amount, date, note
        case fromAccountID = "from_account_id"
        case toAccountID = "to_account_id"
    }

    init(_ transfer: AccountTransfer) {
        fromAccountID = transfer.fromAccountID.rawValue
        toAccountID = transfer.toAccountID.rawValue
        amount = transfer.amount.amount
        date = transfer.date.iso
        note = transfer.note
    }
}

/// 只用到 `data.message` 的回應(結帳日出帳結轉、轉帳、撥款報銷)。
struct MessageDTO: Decodable {
    let message: String
}

private struct PaymentBody: Encodable {
    let bankAccountID: String
    let creditCardID: String
    let amount: Decimal
    let date: String
    let note: String
    let isShared: Int

    enum CodingKeys: String, CodingKey {
        case amount, date, note
        case bankAccountID = "bank_account_id"
        case creditCardID = "credit_card_id"
        case isShared = "is_shared"
    }

    init(_ payment: CardPayment) {
        bankAccountID = payment.bankAccountID.rawValue
        creditCardID = payment.creditCardID.rawValue
        amount = payment.amount.amount
        date = payment.date.iso
        note = payment.note
        isShared = payment.isShared ? 1 : 0
    }
}

/// `POST` 與 `PUT /accounts` 的 body。
///
/// 現金錢包和銀行存款帳戶不送信用額度與日期(`nil` 不會被編碼);`is_joint` 一定要送，
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
        case .cash(let wallet):
            type = "cash"
            name = wallet.name
            balance = wallet.balance.amount
            unbilled = 0
            creditLimit = nil
            statementDay = nil
            paymentDueDay = nil
            color = wallet.colorHex
            isJoint = wallet.isJointFund ? 1 : 0
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
            isJoint = card.isJointFund ? 1 : 0
        }
    }
}

/// `GET /accounts` 的一筆:資料表欄位，所以是 snake_case。
///
/// `balance` 一詞兩義：現金錢包和銀行存款帳戶是餘額，信用卡帳戶是已出帳待繳金額(CLAUDE.md「規則」)。
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
    /// 欠款公私拆解，只有信用卡帳戶有。
    let sharedDebt: Decimal?
    let personalDebt: Decimal?

    enum CodingKeys: String, CodingKey {
        case id, name, type, balance, unbilled, color
        case sharedDebt = "shared_debt"
        case personalDebt = "personal_debt"
        case creditLimit = "credit_limit"
        case statementDay = "statement_day"
        case paymentDueDay = "payment_due_day"
        case isJoint = "is_joint"
    }

    /// 不認得的類型是 `nil`,由呼叫端略過。
    func account() -> Account? {
        switch type {
        case "cash":
            return .cash(CashWallet(
                id: AccountID(id), name: name, colorHex: color, balance: Money(balance), isJointFund: isJoint == 1
            ))
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
                paymentDueDay: paymentDueDay,
                sharedDebt: Money(sharedDebt ?? 0),
                personalDebt: Money(personalDebt ?? 0),
                isJointFund: isJoint == 1
            ))
        default:
            return nil
        }
    }
}

/// `GET /accounts/balance`:計算出來的指標，所以是 camelCase。
private struct BalanceSummaryDTO: Decodable {
    /// `bd0507b` 才有;以前的後端沒有這個欄位，也就沒有現金錢包。
    let cashTotal: Decimal?
    let bankTotal: Decimal
    let ccBilled: Decimal
    let ccUnbilled: Decimal
    let available: Decimal
    let monthlyFixed: Decimal
    let monthlyGoals: Decimal
    let disposable: Decimal

    var summary: BalanceSummary {
        BalanceSummary(
            cashTotal: Money(cashTotal ?? 0),
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
