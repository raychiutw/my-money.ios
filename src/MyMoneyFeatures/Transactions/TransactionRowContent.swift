import Foundation
import MyMoneyDomain

/// 一列收支明細要呈現的全部內容(#208 第 5 項):標題、次要文字、帳戶、金額、圖示與 VoiceOver 整句,
/// 由這個 module 一次決定;`TransactionRow` 只負責排版。
public struct TransactionRowContent: Equatable, Sendable {
    /// 備註，沒有備註時用分類名稱。
    public let title: String
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
        // 次要文字「記帳人・歸屬」(#145):自己記的也顯示;系統自動產生的紀錄記帳人寫「系統紀錄」;沒有記帳人名稱時只寫歸屬。
        subtitle = TransactionSubtitle(
            recorder: transaction.isSystemRecord ? "系統紀錄" : transaction.recorderName,
            ownership: OwnershipName.title(isShared: transaction.isShared),
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
