import Foundation
import MyMoneyDomain
import Observation

/// 新增或編輯資金帳戶的 sheet(parity.md「帳戶」)。
@MainActor
@Observable
public final class AccountEditorModel {
    /// 新增時可以切換類型，切換後套用該類型的預設值;編輯時不能改類型(後端的 PUT 也不接受)。
    ///
    /// 不用 `didSet` 把值改回去:`@Observable` 會把屬性改寫成 setter,在 `didSet` 裡指派會無限遞迴。
    public var kind: AccountKind {
        get { storedKind }
        set {
            guard canChangeKind, newValue != storedKind else { return }
            storedKind = newValue
            applyDefaults(for: newValue)
        }
    }

    private var storedKind: AccountKind

    public var name = ""
    public var colorHex: String

    /// 現金錢包和銀行存款帳戶的餘額。信用卡不輸入已出帳待繳款(web 在 `82d9124` 拿掉了)。
    public var amountText = ""
    public var unbilledText = ""
    public var creditLimitText = ""
    public var statementDay: Int?
    public var paymentDueDay: Int?

    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    public var title: String {
        let action = editingID == nil ? "新增" : "編輯"
        let noun = switch kind {
        case .cash: "現金錢包"
        case .bank: "銀行存款帳戶"
        case .creditCard: "信用卡"
        }
        return action + noun
    }

    /// 信用卡沒有餘額欄：新增時已出帳待繳款送 0,編輯時照原值送回。
    public var showsAmountField: Bool { kind != .creditCard }

    public var amountLabel: String {
        kind == .cash ? "目前現金餘額" : "餘額"
    }

    public var canChangeKind: Bool { editingID == nil }

    @ObservationIgnored private let editingID: AccountID?

    /// 編輯信用卡時原本的已出帳待繳款(表單不能改，照原值送回);新增時是 0。
    @ObservationIgnored private var originalBilledDebt: Money = .zero

    /// 新增時隨機挑的代表色;現金錢包改用固定的綠色(見 `applyDefaults`)。
    @ObservationIgnored private var randomDefaultColor = ""

    /// 家庭公用(家庭共同基金、家庭卡)或個人私帳，所有類型都能設。編輯時帶入原本的標記：
    /// 後端的 PUT 沒收到 `is_joint` 會寫成 0。
    public var isJointFund: Bool
    @ObservationIgnored private let repository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion

    public init(
        adding kind: AccountKind,
        repository: any AccountRepository,
        dataVersion: DataVersion,
        randomColor: () -> String = AccountColors.random
    ) {
        storedKind = kind
        randomDefaultColor = randomColor()
        colorHex = randomDefaultColor
        editingID = nil
        isJointFund = false
        self.repository = repository
        self.dataVersion = dataVersion
        applyDefaults(for: kind)
    }

    public init(editing account: Account, repository: any AccountRepository, dataVersion: DataVersion) {
        editingID = account.id
        self.repository = repository
        self.dataVersion = dataVersion
        switch account {
        case .cash(let wallet):
            storedKind = .cash
            name = wallet.name
            colorHex = wallet.colorHex
            amountText = Self.text(wallet.balance)
            isJointFund = wallet.isJointFund
        case .bank(let bank):
            storedKind = .bank
            name = bank.name
            colorHex = bank.colorHex
            amountText = Self.text(bank.balance)
            unbilledText = "0"
            isJointFund = bank.isJointFund
        case .creditCard(let card):
            storedKind = .creditCard
            name = card.name
            colorHex = card.colorHex
            originalBilledDebt = card.billedDebt
            unbilledText = Self.text(card.unbilledDebt)
            creditLimitText = card.creditLimit.map(Self.text) ?? ""
            statementDay = card.statementDay
            paymentDueDay = card.paymentDueDay
            isJointFund = card.isJointFund
        }
    }

    /// 儲存;成功時回傳 `true`(sheet 關閉),並遞增資料版本讓其他畫面重抓。
    public func save() async -> Bool {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "請輸入帳戶名稱"
            return false
        }
        let draft = draft(named: trimmedName)
        isSaving = true
        defer { isSaving = false }
        do {
            if let editingID {
                try await repository.update(editingID, with: draft)
            } else {
                try await repository.create(draft)
            }
            dataVersion.bump()
            return true
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "儲存帳戶失敗" : message
            return false
        }
    }

    private func draft(named name: String) -> AccountDraft {
        switch kind {
        case .cash:
            .cash(CashWalletDraft(
                name: name, colorHex: colorHex, balance: Self.money(amountText), isJointFund: isJointFund
            ))
        case .bank:
            .bank(BankAccountDraft(
                name: name, colorHex: colorHex, balance: Self.money(amountText), isJointFund: isJointFund
            ))
        case .creditCard:
            .creditCard(CreditCardDraft(
                name: name,
                colorHex: colorHex,
                billedDebt: originalBilledDebt,
                unbilledDebt: Self.money(unbilledText),
                creditLimit: Self.optionalMoney(creditLimitText),
                statementDay: statementDay,
                paymentDueDay: paymentDueDay,
                isJointFund: isJointFund
            ))
        }
    }

    /// 新增時各類型的預設值(web 的 handleOpenAdd)。web 預填的金額「0」在 iOS 是 placeholder,
    /// 欄位留空，存的時候一樣是 0:預填的「0」會讓游標停在 0 前面，輸入的數字接在 0 前面。
    private func applyDefaults(for kind: AccountKind) {
        unbilledText = ""
        colorHex = kind == .cash ? AccountColors.cashWallet : randomDefaultColor
        switch kind {
        case .cash, .bank:
            creditLimitText = ""
            statementDay = nil
            paymentDueDay = nil
        case .creditCard:
            creditLimitText = "100000"
            statementDay = 15
            paymentDueDay = 5
        }
    }

    /// 跟 web 的 `parseFloat(x) || 0` 一樣：不是數字就當 0。
    private static func money(_ text: String) -> Money {
        optionalMoney(text) ?? .zero
    }

    /// 空白或不是數字時是 `nil`(信用額度選填)。
    private static func optionalMoney(_ text: String) -> Money? {
        Decimal(string: text.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX")).map(Money.init)
    }

    private static func text(_ money: Money) -> String {
        "\(money.amount)"
    }
}

/// 資金帳戶可選的 8 種代表色(web 的 ACCOUNT_COLORS),附 VoiceOver 念的名稱。
public enum AccountColors {
    public static let all: [(hex: String, name: String)] = [
        ("#FF8A8A", "珊瑚粉"),
        ("#FFD4A0", "杏桃"),
        ("#A8D8EA", "天空藍"),
        ("#95E1D3", "薄荷綠"),
        ("#F38181", "玫瑰紅"),
        ("#FCE38A", "檸檬黃"),
        ("#EAFFD0", "淺綠"),
        ("#C9D6FF", "薰衣草"),
    ]

    /// 新增現金錢包的預設色(web 的 `openAdd`),不在 8 色裡。
    public static let cashWallet = "#10B981"

    public static func random() -> String {
        all.randomElement()!.hex
    }
}
