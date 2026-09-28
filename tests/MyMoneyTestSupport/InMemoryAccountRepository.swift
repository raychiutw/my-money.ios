import Foundation
import MyMoneyDomain

/// 不連網路的資金帳戶:資料由測試決定，也可以指定失敗。
public actor InMemoryAccountRepository: AccountRepository {
    private var storedAccounts: [Account]
    private var summary: BalanceSummary
    private var failure: RepositoryError?
    private let gate: Gate?

    /// 新增過的內容，依送出順序。
    public private(set) var createdDrafts: [AccountDraft] = []

    /// 最後一次編輯的內容，依資金帳戶。
    public private(set) var updatedDrafts: [AccountID: AccountDraft] = [:]

    /// 刪除過的資金帳戶，依刪除順序。
    public private(set) var deletedIDs: [AccountID] = []

    /// `accounts()` 被呼叫的次數，用來確認有沒有重抓。
    public private(set) var fetchCount = 0

    public init(accounts: [Account], summary: BalanceSummary, gate: Gate? = nil) {
        storedAccounts = accounts
        self.summary = summary
        self.gate = gate
    }

    public func accounts() async throws -> [Account] {
        await gate?.pass()
        fetchCount += 1
        if let failure { throw failure }
        return storedAccounts
    }

    public func balanceSummary() async throws -> BalanceSummary {
        await gate?.pass()
        if let failure { throw failure }
        return summary
    }

    public func create(_ draft: AccountDraft) async throws {
        if let failure { throw failure }
        createdDrafts.append(draft)
        storedAccounts.append(Self.account(AccountID("in-memory-account-\(createdDrafts.count)"), from: draft))
    }

    public func update(_ id: AccountID, with draft: AccountDraft) async throws {
        if let failure { throw failure }
        updatedDrafts[id] = draft
        storedAccounts = storedAccounts.map { $0.id == id ? Self.account(id, from: draft) : $0 }
    }

    public func delete(_ id: AccountID) async throws {
        if let failure { throw failure }
        deletedIDs.append(id)
        storedAccounts.removeAll { $0.id == id }
    }

    /// 後端建立或更新後的資金帳戶(不重算資金指標)。
    private static func account(_ id: AccountID, from draft: AccountDraft) -> Account {
        switch draft {
        case .cash(let wallet):
            .cash(CashWallet(
                id: id, name: wallet.name, colorHex: wallet.colorHex, balance: wallet.balance, isJointFund: wallet.isJointFund
            ))
        case .bank(let bank):
            .bank(BankAccount(
                id: id, name: bank.name, colorHex: bank.colorHex, balance: bank.balance, isJointFund: bank.isJointFund
            ))
        case .creditCard(let card):
            .creditCard(CreditCard(
                id: id,
                name: card.name,
                colorHex: card.colorHex,
                billedDebt: card.billedDebt,
                unbilledDebt: card.unbilledDebt,
                creditLimit: card.creditLimit,
                statementDay: card.statementDay,
                paymentDueDay: card.paymentDueDay,
                isJointFund: card.isJointFund
            ))
        }
    }

    /// 信用卡還款沖銷送出過的內容，依送出順序。
    public private(set) var payments: [CardPayment] = []

    /// 結帳日出帳結轉過的信用卡帳戶，依順序。
    public private(set) var rolledOverIDs: [AccountID] = []

    /// 跟後端一樣：從銀行存款帳戶扣款，先沖已出帳待繳金額，不足的部分再沖未出帳金額(不重算資金指標與欠款公私拆解)。
    public func payCreditCard(_ payment: CardPayment) async throws {
        if let failure { throw failure }
        payments.append(payment)
        storedAccounts = storedAccounts.map { account in
            switch account {
            case .bank(let bank) where bank.id == payment.bankAccountID:
                return .bank(BankAccount(
                    id: bank.id, name: bank.name, colorHex: bank.colorHex, balance: bank.balance - payment.amount,
                    isJointFund: bank.isJointFund
                ))
            case .creditCard(let card) where card.id == payment.creditCardID:
                let billed = max(card.billedDebt - payment.amount, .zero)
                let rest = payment.amount - (card.billedDebt - billed)
                return .creditCard(Self.card(card, billed: billed, unbilled: max(card.unbilledDebt - rest, .zero)))
            default:
                return account
            }
        }
    }

    /// 跟後端一樣把未出帳金額移到已出帳待繳金額;沒有未出帳金額時拒絕。
    public func rollOverStatement(_ id: AccountID) async throws -> String {
        if let failure { throw failure }
        guard case .creditCard(let card)? = storedAccounts.first(where: { $0.id == id }), card.unbilledDebt > .zero else {
            throw RepositoryError.rejected("目前無未出帳金額需結轉")
        }
        rolledOverIDs.append(id)
        storedAccounts = storedAccounts.map {
            $0.id == id ? .creditCard(Self.card(card, billed: card.totalDue, unbilled: .zero)) : $0
        }
        return "已將未出帳 \(card.unbilledDebt.amount.formatted(.currency(code: "TWD").precision(.fractionLength(0)).locale(Locale(identifier: "zh_Hant_TW")))) 成功結轉為已出帳待繳！"
    }

    private static func card(_ card: CreditCard, billed: Money, unbilled: Money) -> CreditCard {
        CreditCard(
            id: card.id, name: card.name, colorHex: card.colorHex, billedDebt: billed, unbilledDebt: unbilled,
            creditLimit: card.creditLimit, statementDay: card.statementDay, paymentDueDay: card.paymentDueDay,
            sharedDebt: card.sharedDebt, personalDebt: card.personalDebt, isJointFund: card.isJointFund
        )
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    /// 換成新的資料(模擬家人在別的裝置上改了資料)。
    public func replace(accounts: [Account], summary: BalanceSummary) {
        storedAccounts = accounts
        self.summary = summary
    }
}

extension InMemoryAccountRepository {
    /// 對應 `accounts-list.json` 與 `accounts-balance.json` 的測試資料:一個銀行存款帳戶、兩張信用卡帳戶。
    public static func sample(gate: Gate? = nil) -> InMemoryAccountRepository {
        InMemoryAccountRepository(accounts: SampleAccounts.all, summary: SampleAccounts.summary, gate: gate)
    }

    /// 同上，再加一個現金錢包「iOS 測試皮夾」1,500(對應 `accounts-list-with-cash.json`)。
    public static func sampleWithCash(gate: Gate? = nil) -> InMemoryAccountRepository {
        InMemoryAccountRepository(
            accounts: [.cash(SampleAccounts.wallet)] + SampleAccounts.all, summary: SampleAccounts.summaryWithCash, gate: gate
        )
    }
}

/// 畫面 model 測試與 UI 測試共用的資金帳戶。
public enum SampleAccounts {
    public static let savings = BankAccount(
        id: AccountID("sample-bank"),
        name: "iOS 測試存款",
        colorHex: "#A8D8EA",
        balance: Money(50000),
        isJointFund: false
    )

    public static let card = CreditCard(
        id: AccountID("sample-card"),
        name: "iOS 測試信用卡",
        colorHex: "#FFD4A0",
        billedDebt: Money(12000),
        unbilledDebt: Money(3500),
        creditLimit: Money(100_000),
        statementDay: 15,
        paymentDueDay: 5,
        sharedDebt: Money(3000),
        personalDebt: Money(12500)
    )

    /// 剩餘額度 7,000,低於 10,000 的警示門檻。
    public static let lowLimitCard = CreditCard(
        id: AccountID("sample-low-limit-card"),
        name: "iOS 測試小額卡",
        colorHex: "#F38181",
        billedDebt: Money(8000),
        unbilledDebt: Money(5000),
        creditLimit: Money(20000),
        statementDay: 1,
        paymentDueDay: 20
    )

    public static let all: [Account] = [.bank(savings), .creditCard(card), .creditCard(lowLimitCard)]

    /// 個人私帳的現金錢包。
    public static let wallet = CashWallet(
        id: AccountID("sample-wallet"), name: "iOS 測試皮夾", colorHex: "#10B981", balance: Money(1500), isJointFund: false
    )

    /// 含現金錢包的資金指標：淨可用餘額 = 1,500 + 50,000 − 28,500(後端算好的值)。
    public static let summaryWithCash = BalanceSummary(
        cashTotal: Money(1500),
        bankBalanceTotal: Money(50000),
        billedDebtTotal: Money(20000),
        unbilledDebtTotal: Money(8500),
        availableBalance: Money(23000),
        monthlyAmortization: .zero,
        monthlySavingsReserve: .zero,
        disposableCash: Money(23000)
    )

    public static let summary = BalanceSummary(
        bankBalanceTotal: Money(50000),
        billedDebtTotal: Money(20000),
        unbilledDebtTotal: Money(8500),
        availableBalance: Money(21500),
        monthlyAmortization: .zero,
        monthlySavingsReserve: .zero,
        disposableCash: Money(21500)
    )
}
