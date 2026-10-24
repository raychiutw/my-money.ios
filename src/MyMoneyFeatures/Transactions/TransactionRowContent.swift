import Foundation
import MyMoneyDomain

/// 一列收支明細要呈現的全部內容(#208 第 5 項):標題、次要文字、帳戶、金額、圖示與 VoiceOver 整句,
/// 由這個 module 一次決定;`TransactionRow` 只負責排版。
public struct TransactionRowContent: Equatable, Sendable {
    /// 備註，沒有備註時用分類名稱。(⋯ 選單與 VoiceOver 用;明細卡的標題是 `categoryTitle`。)
    public let title: String
    /// 明細卡第一排的標題:分類中文(系統分類用系統分類名稱,#287)。
    public let categoryTitle: String
    /// 明細卡第三排的備註;沒有備註是 `nil`(整排不出現)。
    public let note: String?
    /// 明細卡第二排的膠囊,順序固定:歸屬、銷帳狀態(待報銷、已撥款、已額外處理)、信用卡出帳狀態(已出帳、延至下期)、帳戶;
    /// 沒有的不放。
    public let chips: [String]
    /// 同 `chips`,多帶是否要強調(「待報銷」用淡粉色):樣式由內容決定,畫面不比對字串。
    public let chipItems: [CardChip]
    /// 建檔人頭像裡的字:名字第一個字(大寫);系統紀錄是「系」;沒有建檔人是 `nil`(不放頭像)。
    public let avatarInitial: String?
    /// 系統自動產生的紀錄(頭像用灰色)。
    public let isSystemRecord: Bool
    public let subtitle: TransactionSubtitle
    /// 資產帳戶名稱;沒有帳戶名稱就不佔一行。
    public let accountName: String?
    public let amount: AmountPresentation
    public let symbolName: String
    /// 只有不是自己記的才有(#72);VoiceOver 才念誰記的。用 ID 判斷，家人可能同名。
    public let spokenRecorder: String?
    /// 例如「餐飲，午餐，帳戶 iOS 測試存款，家庭公帳，支出 120 元」。沒有備註時不重複念分類。
    public let spokenText: String

    /// `viewer`:目前登入的人(骨架屏等沒有 model 時是 `nil`)。
    public init(_ transaction: Transaction, viewer: UserID?) {
        title = transaction.note.isEmpty ? transaction.category.name : transaction.note
        categoryTitle = transaction.category.name
        note = transaction.note.isEmpty ? nil : transaction.note
        isSystemRecord = transaction.isSystemRecord
        avatarInitial = transaction.isSystemRecord
            ? "系" : transaction.recorderName.flatMap { $0.first }.map { String($0).uppercased() }
        chipItems = Self.chipItems(of: transaction)
        chips = chipItems.map(\.text)
        // 次要文字「記帳人・歸屬」(#145):自己記的也顯示;系統自動產生的紀錄記帳人寫「系統紀錄」;沒有記帳人名稱時只寫歸屬。
        subtitle = TransactionSubtitle(
            recorder: transaction.isSystemRecord ? "系統紀錄" : transaction.recorderName,
            ownership: OwnershipName.title(isShared: transaction.isShared, payment: transaction.householdPayment),
            billing: transaction.billing.label,
            time: transaction.recordedAt.map(RecordedTime.clockText(of:))
        )
        accountName = transaction.accountName
        amount = transaction.amountPresentation
        symbolName = transaction.category.symbolName
        let recorder: String? = {
            guard let viewer, transaction.recorderID == viewer else { return transaction.recorderName }
            return nil
        }()
        spokenRecorder = recorder

        var parts = [transaction.category.name]
        if !transaction.note.isEmpty { parts.append(transaction.note) }
        parts.append("帳戶 \(transaction.accountName ?? "預設帳戶")")
        if let time = RecordedTime.spokenText(of: transaction.recordedAt) { parts.append(time) }
        if let recorder { parts.append("記帳人 \(recorder)") }
        parts.append(subtitle.ownership)
        if let billing = subtitle.billing { parts.append(billing) }
        parts.append((transaction.type == .income ? "收入 " : "支出 ") + transaction.amount.spokenText)
        spokenText = parts.joined(separator: "，")
    }
}

/// 明細卡上的一顆膠囊(#287):文字,以及要不要強調(淡粉色)。
public struct CardChip: Equatable, Sendable {
    public let text: String
    public let isHighlighted: Bool

    public init(_ text: String, isHighlighted: Bool = false) {
        self.text = text
        self.isHighlighted = isHighlighted
    }
}

extension TransactionRowContent {
    /// 膠囊清單(#287):歸屬、銷帳狀態、出帳狀態、帳戶。
    fileprivate static func chipItems(of transaction: Transaction) -> [CardChip] {
        var chips = [CardChip(OwnershipName.title(isShared: transaction.isShared))]
        if transaction.isShared {
            switch transaction.householdPayment {
            case .advancePending: chips.append(CardChip(Terms.pendingReimbursement, isHighlighted: true))
            case .advanceReimbursed: chips.append(CardChip(Terms.reimbursedPayout))
            case .advanceHandledSeparately: chips.append(CardChip(Terms.handledSeparately))
            case nil, .jointFund: break
            }
        }
        if let billing = transaction.billing.label { chips.append(CardChip(billing)) }
        if let account = transaction.accountName, !account.isEmpty { chips.append(CardChip(account)) }
        return chips
    }
}

/// 交易列的次要文字:記帳人與歸屬分開存放，畫面放不下時先截記帳人的名稱、歸屬保留(#145)。
public struct TransactionSubtitle: Equatable, Sendable {
    public let recorder: String?
    public let ownership: String
    /// 信用卡的帳單狀態標籤「已出帳」「延至下期」(上游 ADR 0020，#188);其他沒有。
    public let billing: String?
    /// 記帳時間(台灣時間 HH:mm,上游 718ace9、#207);沒有時間資料是 `nil`。放在最前面。
    public let time: String?

    public init(recorder: String?, ownership: String, billing: String? = nil, time: String? = nil) {
        self.time = time
        self.recorder = recorder
        self.ownership = ownership
        self.billing = billing
    }

    /// 歸屬加帳單狀態標籤,例如「家庭公帳・延至下期」:畫面放不下時這一段保留，先截記帳人的名稱。
    public var tail: String {
        [ownership, billing].compactMap { $0 }.joined(separator: "・")
    }

    /// 例如「14:05・小美・家庭公帳・延至下期」;沒有時間就沒有最前面那一段,沒有記帳人名稱時只有歸屬(與標籤)。
    public var text: String {
        [time, recorder, tail].compactMap { $0 }.joined(separator: "・")
    }
}

extension BillingStatus {
    /// 列上的標籤;未出帳不標。
    fileprivate var label: String? {
        switch self {
        case .unbilled: nil
        case .billed: Terms.billed
        case .deferred: Terms.deferredToNextStatement
        }
    }
}
