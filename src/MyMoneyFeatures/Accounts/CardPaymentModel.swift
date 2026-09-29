import Foundation
import MyMoneyDomain
import Observation

/// 信用卡扣款還款的 sheet(parity.md「帳戶」的信用卡扣款還款)。
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

    /// 從卡片的哪個按鈕打開(web 的 `handleOpenPay`)。
    public enum Preset: Sendable {
        /// 「繳家庭代墊」:欠款裡家庭公帳的部分，家庭公帳。
        case shared
        /// 「繳個人私帳」:欠款裡個人私帳的部分，個人私帳。
        case personal
        /// 「全額結清」:信用卡待繳總額，家庭公帳。
        case full
    }

    /// 預設值跟 web 一樣：第一個餘額大於 0 的銀行存款帳戶(沒有就用第一個);金額、歸屬依打開的按鈕;
    /// 今天;備註是「信用卡扣款還款「卡名」(家庭代墊／個人私帳／全額)」,不照抄 web 的疊字(parity 刻意偏離第 42 項)。
    public init(
        card: CreditCard,
        preset: Preset,
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
        let (amount, isShared, kind): (Money, Bool, String) = switch preset {
        case .shared: (card.sharedDebt, true, "家庭代墊")
        case .personal: (card.personalDebt, false, "個人私帳")
        case .full: (card.totalDue, true, "全額")
        }
        amountText = amount > .zero ? "\(amount.amount)" : ""
        date = today()
        note = "信用卡扣款還款「\(card.name)」(\(kind))"
        self.isShared = isShared
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
            errorMessage = "繳款金額不可超過信用卡待繳總額 \(card.totalDue.formatted())"
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
