import Foundation
import MyMoneyDomain
import Observation

/// 信用卡還款沖銷的 sheet(parity.md「帳戶」的信用卡還款沖銷)。
@MainActor
@Observable
public final class CardPaymentModel {
    public enum Outcome: Equatable {
        case invalid
        /// 扣款帳戶的餘額小於繳款金額，要先確認。
        case needsConfirmation
        case paid
        case failed
    }

    public let card: CreditCard
    /// 扣款帳戶只列出銀行存款帳戶。
    public let bankAccounts: [BankAccount]

    public var bankAccountID: AccountID?
    public var amountText: String
    public var date: CalendarDay
    public var note: String
    public var isShared: Bool

    public private(set) var errorMessage: String?
    public private(set) var lowBalanceConfirmation: String?
    public private(set) var isSaving = false

    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion

    /// 預設值跟 web 一樣：第一個餘額大於 0 的銀行存款帳戶(沒有就用第一個);
    /// 金額在已出帳待繳金額大於 0 時用它，否則用未出帳金額;今天;「繳納【卡名】卡費」;公帳部分較多時是家庭公帳。
    public init(
        card: CreditCard,
        bankAccounts: [BankAccount],
        repository: any AccountRepository,
        dataVersion: DataVersion,
        today: () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.card = card
        self.bankAccounts = bankAccounts
        self.repository = repository
        self.dataVersion = dataVersion
        bankAccountID = (bankAccounts.first { $0.balance > .zero } ?? bankAccounts.first)?.id
        let amount = card.billedDebt > .zero ? card.billedDebt : card.unbilledDebt
        amountText = amount > .zero ? "\(amount.amount)" : ""
        date = today()
        note = "繳納【\(card.name)】卡費"
        isShared = card.sharedDebt >= card.personalDebt
    }

    /// 「繳家庭代墊 X」;公帳部分是 0 時不顯示(`nil`)。
    public var sharedQuickFillTitle: String? {
        card.sharedDebt > .zero ? "繳家庭代墊 \(card.sharedDebt.formatted())" : nil
    }

    /// 「繳個人私帳 X」;私帳部分是 0 時不顯示(`nil`)。
    public var personalQuickFillTitle: String? {
        card.personalDebt > .zero ? "繳個人私帳 \(card.personalDebt.formatted())" : nil
    }

    /// 帶入公帳金額，並優先選家庭共同基金。
    public func fillShared() {
        amountText = "\(card.sharedDebt.amount)"
        isShared = true
        if let joint = bankAccounts.first(where: \.isJointFund) { bankAccountID = joint.id }
    }

    /// 帶入私帳金額，並優先選非共同基金的帳戶。
    public func fillPersonal() {
        amountText = "\(card.personalDebt.amount)"
        isShared = false
        if let own = bankAccounts.first(where: { !$0.isJointFund }) { bankAccountID = own.id }
    }

    /// 送出。扣款帳戶的餘額小於繳款金額時先回 `.needsConfirmation`,確認後帶 `confirmedLowBalance: true` 再送一次。
    public func submit(confirmedLowBalance: Bool = false) async -> Outcome {
        errorMessage = nil
        lowBalanceConfirmation = nil
        guard let bankAccountID, let bank = bankAccounts.first(where: { $0.id == bankAccountID }) else {
            errorMessage = "請選擇扣款銀行帳戶"
            return .invalid
        }
        guard let amount = Money(wholeNumber: amountText), amount > .zero else {
            errorMessage = "請輸入大於 0 的繳款金額"
            return .invalid
        }
        if card.totalDue > .zero, card.totalDue < amount {
            errorMessage = "繳款金額不可超過當前待繳總額 \(card.totalDue.formatted())"
            return .invalid
        }
        if bank.balance < amount, !confirmedLowBalance {
            lowBalanceConfirmation = "扣款帳戶「\(bank.name)」目前餘額是 \(bank.balance.formatted()),小於繳款金額 \(amount.formatted())。確定仍要繼續扣款嗎？"
            return .needsConfirmation
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.payCreditCard(CardPayment(
                bankAccountID: bankAccountID, creditCardID: card.id, amount: amount, date: date,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines), isShared: isShared
            ))
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "繳款失敗" : message
            return .failed
        }
        dataVersion.bump()
        return .paid
    }
}

extension CreditCard {
    /// 欠款公私拆解裡家庭公帳的佔比，取整數，例如「15%」(跟 web 的 `Math.round` 一樣)。
    public var sharedDebtPercentText: String {
        guard totalDue > .zero else { return "0%" }
        let percent = sharedDebt.amount / totalDue.amount * 100
        return percent.percentText(fractionDigits: 0)
    }
}
