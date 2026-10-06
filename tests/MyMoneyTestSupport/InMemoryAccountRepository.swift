import Foundation
import MyMoneyDomain

/// 不連網路的資產帳戶:資料由測試決定，也可以指定失敗。
public actor InMemoryAccountRepository: AccountRepository {
    private var storedAccounts: [Account]
    private var summary: BalanceSummary
    private var failure: RepositoryError?
    private let gate: Gate?

    /// 新增過的內容，依送出順序。
    public private(set) var createdDrafts: [AccountDraft] = []

    /// 最後一次編輯的內容，依資產帳戶。
    public private(set) var updatedDrafts: [AccountID: AccountDraft] = [:]

    /// 刪除過的資產帳戶，依刪除順序。
    public private(set) var deletedIDs: [AccountID] = []

    /// `accounts()` 被呼叫的次數，用來確認有沒有重抓。
    public private(set) var fetchCount = 0

    public init(accounts: [Account], summary: BalanceSummary, gate: Gate? = nil) {
        storedAccounts = accounts
        self.summary = summary
        self.gate = gate
    }

    /// 停在 gate 的查詢放行後，跟 URLSession 一樣：工作已經被取消時丟出 `CancellationError`。
    private func checkCancellationIfGated() throws {
        if gate != nil { try Task.checkCancellation() }
    }

    /// 每次查詢帶的帳戶檢視範圍，依順序。
    public private(set) var requestedScopes: [AccountScope] = []

    /// 跟後端一樣依範圍篩選(這裡的帳戶都算本人的):公帳範圍只留歸屬公帳的，加上有家庭代墊欠款的個人信用卡;私帳範圍只留私帳。
    public func accounts(scope: AccountScope) async throws -> [Account] {
        await gate?.pass()
        try checkCancellationIfGated()
        fetchCount += 1
        requestedScopes.append(scope)
        if let failure { throw failure }
        return switch scope {
        // 他人的私卡(脫敏的)只在公帳範圍看得到。
        case .all: storedAccounts.filter { !$0.isMaskedCard }
        // 跟後端(上游 ADR 0015)一樣:公帳範圍除了歸屬公帳的帳戶，還有「有家庭代墊欠款的個人信用卡」。
        case .household: storedAccounts.filter { $0.isJointFund || $0.hasSharedDebt }
        case .personal: storedAccounts.filter { !$0.isJointFund && !$0.isMaskedCard }
        }
    }

    /// 每次查詢資金指標帶的帳戶檢視範圍，依順序。
    public private(set) var requestedSummaryScopes: [AccountScope] = []

    /// 資金指標由後端算好，這裡回傳設定好的值(不依範圍重算)。
    public func balanceSummary(scope: AccountScope) async throws -> BalanceSummary {
        await gate?.pass()
        try checkCancellationIfGated()
        requestedSummaryScopes.append(scope)
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

    /// 後端建立或更新後的資產帳戶(不重算資金指標)。
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

    /// 信用卡扣款還款送出過的內容，依送出順序。
    public private(set) var payments: [CardPayment] = []

    /// 做過結帳日出帳作業的信用卡帳戶，依順序。
    public private(set) var rolledOverIDs: [AccountID] = []

    /// 跟後端一樣：從活存帳戶扣款，先沖已出帳待繳款，不足的部分再沖未出帳款(不重算資金指標與欠款公私拆解)。
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
                // 後端是用最近的支出估算公帳、私帳各占多少;這裡簡化成:公帳的還款沖公帳，私帳的還款沖私帳。
                let shared = payment.isShared ? max(card.sharedDebt - payment.amount, .zero) : card.sharedDebt
                let personal = payment.isShared ? card.personalDebt : max(card.personalDebt - payment.amount, .zero)
                return .creditCard(Self.card(
                    card, billed: billed, unbilled: max(card.unbilledDebt - rest, .zero), shared: shared, personal: personal
                ))
            default:
                return account
            }
        }
    }

    /// 跟後端一樣把未出帳款移到已出帳待繳款;沒有未出帳款時拒絕。
    public func rollOverStatement(_ id: AccountID) async throws -> String {
        if let failure { throw failure }
        guard case .creditCard(let card)? = storedAccounts.first(where: { $0.id == id }), card.unbilledDebt > .zero else {
            // 後端 `f32ff6c` 的原文(B:handlers/accounts.ts@f32ff6c:262):後端的訊息還沒改用正名，照抄。
            throw RepositoryError.rejected("目前無未出帳金額需出帳作業")
        }
        rolledOverIDs.append(id)
        storedAccounts = storedAccounts.map {
            $0.id == id ? .creditCard(Self.card(card, billed: card.totalDue, unbilled: .zero)) : $0
        }
        // 後端 `f32ff6c` 的原文(B:handlers/accounts.ts@f32ff6c:274),疊字已回報 onion523/my-money#27。
        return "帳單出帳作業完成！已轉入已出帳待繳款。"
    }

    /// 校準過未出帳的信用卡，依順序。
    public private(set) var reconciledIDs: [AccountID] = []

    /// 後端是從收支明細重算未出帳款;這裡拿不到收支明細，未出帳款維持原值，只回傳跟後端同格式的訊息。
    public func reconcileUnbilled(_ id: AccountID) async throws -> String {
        await gate?.pass()
        if let failure { throw failure }
        guard case .creditCard(let card)? = storedAccounts.first(where: { $0.id == id }) else {
            throw RepositoryError.rejected("信用卡不存在或無權限")
        }
        reconciledIDs.append(id)
        // 後端 `f32ff6c` 的原文(B:handlers/accounts.ts@f32ff6c:387):後端的訊息還沒改用正名，照抄。
        return "已自動校準「\(card.name)」未出帳金額為 NT$ \(card.unbilledDebt.backendText)"
    }

    private static func card(_ card: CreditCard, billed: Money, unbilled: Money, shared: Money? = nil, personal: Money? = nil) -> CreditCard {
        CreditCard(
            id: card.id, name: card.name, colorHex: card.colorHex, billedDebt: billed, unbilledDebt: unbilled,
            creditLimit: card.creditLimit, statementDay: card.statementDay, paymentDueDay: card.paymentDueDay,
            sharedDebt: shared ?? card.sharedDebt, personalDebt: personal ?? card.personalDebt, isJointFund: card.isJointFund,
            ownerID: card.ownerID, ownerName: card.ownerName, isMasked: card.isMasked
        )
    }

    /// ATM 提款／帳戶互轉送出過的內容，依送出順序。
    public private(set) var transfers: [AccountTransfer] = []

    /// 跟後端一樣：同一個帳戶、轉出的現金或活存帳戶餘額不足時拒絕;成功時兩邊的餘額都更新。
    public func transfer(_ transfer: AccountTransfer) async throws -> String {
        await gate?.pass()
        if let failure { throw failure }
        guard transfer.fromAccountID != transfer.toAccountID else {
            throw RepositoryError.rejected("轉出與轉入帳戶不能相同")
        }
        guard
            let from = storedAccounts.first(where: { $0.id == transfer.fromAccountID }),
            let to = storedAccounts.first(where: { $0.id == transfer.toAccountID })
        else {
            throw RepositoryError.rejected("找不到轉出帳戶或無權限操作")
        }
        if let balance = Self.balance(of: from), balance < transfer.amount {
            // 後端 `f32ff6c` 的原文(B:handlers/accounts.ts@f32ff6c:466、491)。
            throw RepositoryError.rejected("轉出帳戶餘額不足（目前餘額：NT$ \(balance.backendText)）")
        }
        transfers.append(transfer)
        storedAccounts = storedAccounts.map { account in
            if account.id == from.id { return Self.adding(.zero - transfer.amount, to: account) }
            if account.id == to.id { return Self.adding(transfer.amount, to: account) }
            return account
        }
        let isATM: Bool
        if case .bank = from, case .cash = to { isATM = true } else { isATM = false }
        return "\(isATM ? "ATM 提款" : "內部轉帳")成功 NT$ \(transfer.amount.backendText) (\(from.name) -> \(to.name))"
    }

    /// 現金和活存帳戶的餘額;信用卡沒有(後端不檢查信用卡的餘額)。
    private static func balance(of account: Account) -> Money? {
        switch account {
        case .cash(let wallet): wallet.balance
        case .bank(let bank): bank.balance
        case .creditCard: nil
        }
    }

    /// 跟後端一樣直接加減 `balance`(信用卡的 `balance` 是已出帳待繳款)。
    private static func adding(_ amount: Money, to account: Account) -> Account {
        switch account {
        case .cash(let wallet):
            .cash(CashWallet(
                id: wallet.id, name: wallet.name, colorHex: wallet.colorHex, balance: wallet.balance + amount,
                isJointFund: wallet.isJointFund
            ))
        case .bank(let bank):
            .bank(BankAccount(
                id: bank.id, name: bank.name, colorHex: bank.colorHex, balance: bank.balance + amount,
                isJointFund: bank.isJointFund
            ))
        case .creditCard(let card):
            .creditCard(Self.card(card, billed: card.billedDebt + amount, unbilled: card.unbilledDebt))
        }
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

extension Money {
    /// 後端訊息裡的金額：`toLocaleString()` 加上千分位，例如「NT$ 50,000」的 `50,000`。
    var backendText: String {
        amount.formatted(.number.locale(Locale(identifier: "en_US")))
    }
}

extension InMemoryAccountRepository {
    /// 對應 `accounts-list.json` 與 `accounts-balance.json` 的測試資料:一個活存帳戶、兩張信用卡帳戶。
    public static func sample(gate: Gate? = nil) -> InMemoryAccountRepository {
        InMemoryAccountRepository(accounts: SampleAccounts.all, summary: SampleAccounts.summary, gate: gate)
    }

    /// 同上，再加一個現金「iOS 測試皮夾」1,500(對應 `accounts-list-with-cash.json`)。
    public static func sampleWithCash(gate: Gate? = nil) -> InMemoryAccountRepository {
        InMemoryAccountRepository(
            accounts: [.cash(SampleAccounts.wallet)] + SampleAccounts.all, summary: SampleAccounts.summaryWithCash, gate: gate
        )
    }
}

/// 畫面 model 測試與 UI 測試共用的資產帳戶。擁有者都是登入的範例帳號(編輯權限防呆，上游 ADR 0013、#133)。
public enum SampleAccounts {
    private static let me = InMemoryAuthRepository.Member.sample.user.id

    public static let savings = BankAccount(
        id: AccountID("sample-bank"),
        name: "iOS 測試存款",
        colorHex: "#A8D8EA",
        balance: Money(50000),
        isJointFund: false,
        ownerID: me
    )

    /// 家人(小美)建立的家庭共同基金:一般成員不能編輯、刪除，家庭管理員可以(#133)。
    public static let meiJointFund = BankAccount(
        id: AccountID("sample-mei-joint-fund"),
        name: "小美的共同基金",
        colorHex: "#A8D8EA",
        balance: Money(8000),
        isJointFund: true,
        ownerID: UserID("sample-mei")
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
        personalDebt: Money(12500),
        ownerID: me
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
        paymentDueDay: 20,
        ownerID: me
    )

    public static let all: [Account] = [.bank(savings), .creditCard(card), .creditCard(lowLimitCard)]

    /// 家人(小美)的個人信用卡，替家庭代墊了 1,200:公帳範圍才看得到，經過脫敏(上游 ADR 0015)——
    /// 沒有額度、已出帳 0、未出帳款等於家庭代墊待繳額、個人消費 0。
    public static let meiCardAdvance = CreditCard(
        id: AccountID("sample-mei-card"),
        name: "小美的信用卡",
        colorHex: "#F38181",
        billedDebt: .zero,
        unbilledDebt: Money(1200),
        creditLimit: nil,
        statementDay: 10,
        paymentDueDay: 25,
        sharedDebt: Money(1200),
        personalDebt: .zero,
        ownerID: UserID("sample-mei"),
        ownerName: "小美",
        isMasked: true
    )

    /// 個人私帳的現金。
    public static let wallet = CashWallet(
        id: AccountID("sample-wallet"), name: "iOS 測試皮夾", colorHex: "#10B981", balance: Money(1500), isJointFund: false, ownerID: me
    )

    /// 含現金的資金指標：淨可用餘額 = 1,500 + 50,000 − 28,500(後端算好的值)。
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

extension Account {
    /// 他人的個人信用卡(經過脫敏)。
    fileprivate var isMaskedCard: Bool {
        if case .creditCard(let card) = self { card.isMasked } else { false }
    }

    /// 個人信用卡上有家庭代墊欠款(公帳範圍會看到這張卡)。
    fileprivate var hasSharedDebt: Bool {
        if case .creditCard(let card) = self { !card.isJointFund && card.sharedDebt > .zero } else { false }
    }
}
