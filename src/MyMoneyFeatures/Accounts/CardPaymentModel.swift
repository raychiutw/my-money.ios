import Foundation
import MyMoneyDomain
import Observation

/// 信用卡扣款還款的 sheet(parity.md「帳戶」的信用卡扣款還款)。
@MainActor
@Observable
public final class CardPaymentModel: Submitting {
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
    /// 可用餘額：扣款帳戶的餘額，另起一列顯示(#78)。
    public var availableBalance: Money? {
        bankAccounts.first { $0.id == bankAccountID }?.balance
    }
    public var amountText: String

    /// 「繳家庭代墊」的兩種金額(上游 ADR 0025):只繳當期已出帳的公帳(預設,免得共同基金提早繳到還沒出帳的消費),或結清全部代墊公帳。
    public enum SharedChoice: Hashable, Sendable {
        case billedOnly
        case all
    }

    /// 可以切換的選項:繳家庭代墊、有已出帳公帳、而且它比全部公帳少時才有(兩個金額一樣就不出現)。
    public let sharedChoices: [SharedChoice]

    /// 目前選的金額;切換時金額欄跟著帶入(仍可手動改)。
    public var sharedChoice: SharedChoice = .billedOnly {
        didSet {
            guard oldValue != sharedChoice, sharedChoices.contains(sharedChoice) else { return }
            amountText = Self.amountText(sharedChoice == .billedOnly ? card.defaultSharedPayment : card.sharedDebt)
        }
    }

    public func sharedChoiceTitle(_ choice: SharedChoice) -> String {
        switch choice {
        case .billedOnly: "僅繳當期已出帳公帳 \(card.defaultSharedPayment.formatted())"
        case .all: "結清全部代墊公帳 \(card.sharedDebt.formatted())"
        }
    }

    private static func amountText(_ amount: Money) -> String { amount > .zero ? "\(amount.amount)" : "" }

    public var date: CalendarDay
    public var note: String
    public var isShared: Bool

    /// 繳的是他人的個人信用卡(上游 ADR 0015、#140):只能從共同基金繳家庭代墊，歸屬固定公帳，金額上限是家庭代墊待繳額。
    public let isMaskedCard: Bool

    public package(set) var errorMessage: String?
    public private(set) var lowBalanceConfirmation: String?
    public package(set) var isSaving = false

    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion
    /// 記住上次選的扣款帳戶(#273、#278);`nil` 是不記。
    @ObservationIgnored private let accountMemory: AccountMemory?

    /// 從「繳款」選單的哪個項目打開(web 的 `handleOpenPay`;信用卡詳細頁和精簡列的長按選單，#73)。
    public enum Preset: Sendable {
        /// 「繳家庭代墊」:欠款裡家庭公帳的部分，家庭公帳。
        case shared
        /// 「繳個人私帳」:欠款裡個人私帳的部分，個人私帳。
        case personal
        /// 「全額結清」:信用卡待繳總額，家庭公帳。
        case full
    }

    /// 預設值:扣款帳戶是空的(上游 ADR 0011、#112),**唯一的例外**是這張卡綁定了(使用者自己設定的)預設扣款帳戶、
    /// 而且它在可選清單裡才帶入;金額、歸屬依打開的項目;今天;備註照上游 `97f4789` 的寫法:「扣繳【卡名】卡費 (家庭公帳代墊／個人私帳／全額)」。
    public init(
        card: CreditCard,
        preset: Preset,
        bankAccounts: [BankAccount],
        repository: any AccountRepository,
        dataVersion: DataVersion,
        isMaskedCard: Bool = false,
        accountMemory: AccountMemory? = nil,
        today: () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.accountMemory = accountMemory
        self.card = card
        self.bankAccounts = bankAccounts
        self.repository = repository
        self.dataVersion = dataVersion
        self.isMaskedCard = isMaskedCard
        // 扣款帳戶:不預設「第一個餘額大於 0 的銀行存款帳戶」,要使用者自己選(上游 ADR 0011，#112)。
        // **唯一的例外**:這張卡綁定了預設扣款帳戶(使用者自己設定的,上游 `3d09060`),而且它在這次可選的清單裡,就帶入它——
        // 帶入使用者自己的設定不算擅自預選。他人的私卡(脫敏)不帶入(綁定是對方的私人設定);綁定的帳戶看不到、已刪除也維持空白。
        let bound = isMaskedCard ? nil : card.paymentAccountID.flatMap { id in bankAccounts.contains { $0.id == id } ? id : nil }
        // 優先序:卡片綁定的預設扣款帳戶 ＞ 使用者上次繳款選的帳戶(#278,偏離 ADR 0011，見 `AccountMemory`)＞ 空白。
        bankAccountID = bound ?? accountMemory?.recall(among: bankAccounts.map(Account.bank))
        // 他人的私卡不管從哪個入口打開，都只繳家庭代墊。
        let preset = isMaskedCard ? Preset.shared : preset
        let (amount, isShared, kind): (Money, Bool, String) = switch preset {
        case .shared: (card.defaultSharedPayment, true, "家庭公帳代墊")
        case .personal: (card.personalDebt, false, "個人私帳")
        case .full: (card.totalDue, true, "全額")
        }
        amountText = Self.amountText(amount)
        sharedChoices = preset == .shared && card.hasSharedPaymentChoice ? [.billedOnly, .all] : []
        date = today()
        // 照上游 `97f4789` 的預設備註(W:Accounts.tsx@97f4789:226):半形括號，括號前有一個空格。
        note = "扣繳【\(card.name)】卡費 (\(kind))"
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
        guard let amount = positiveAmount(amountText, label: "繳款金額") else { return .invalid }
        if isMaskedCard {
            if card.sharedDebt > .zero, card.sharedDebt < amount {
                errorMessage = "繳款金額不可超過家庭代墊公帳待繳額 \(card.sharedDebt.formatted())"
                return .invalid
            }
        } else if card.totalDue > .zero, card.totalDue < amount {
            errorMessage = "繳款金額不可超過信用卡待繳總額 \(card.totalDue.formatted())"
            return .invalid
        }
        if bank.balance < amount, !confirmedLowBalance {
            lowBalanceConfirmation = "扣款帳戶「\(bank.name)」目前餘額是 \(bank.balance.formatted()),小於繳款金額 \(amount.formatted())。確定仍要繼續扣款嗎？"
            return .needsConfirmation
        }
        guard await submitting(failure: "繳款失敗", {
            try await repository.payCreditCard(CardPayment(
                bankAccountID: bankAccountID, creditCardID: card.id, amount: amount, date: date,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines), isShared: isShared
            ))
        }) != nil else { return .failed }
        dataVersion.bump()
        accountMemory?.remember(bankAccountID)
        return .paid
    }
}
