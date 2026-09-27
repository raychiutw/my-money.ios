import Foundation
import MyMoneyDomain
import Observation

/// 編輯一筆交易紀錄的 sheet(parity.md「交易」)。家人記的也能編輯;「信用卡還款」不能編輯(不會建立這個 model)。
@MainActor
@Observable
public final class TransactionEditorModel {
    public private(set) var accounts: [Account] = []
    public var isShared: Bool

    /// 切換收支時重設分類，跟記一筆一樣。
    public var type: TransactionType {
        didSet {
            guard type != oldValue else { return }
            category = type == .expense ? .dining : .salary
        }
    }

    public var category: TransactionCategory
    public var amountText: String
    public var note: String
    public var date: CalendarDay
    public var accountID: AccountID?

    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    public let title = "編輯交易紀錄"

    public var categories: [TransactionCategory] {
        let fixed = type == .expense ? TransactionCategory.expenseCategories : TransactionCategory.incomeCategories
        // 機器人記帳可能寫入清單以外的分類;編輯時保留原本的分類可選。
        return fixed.contains(category) ? fixed : fixed + [category]
    }

    @ObservationIgnored private let id: TransactionID
    @ObservationIgnored private let transactions: any TransactionRepository
    @ObservationIgnored private let accountRepository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion

    public init(
        editing transaction: Transaction,
        transactions: any TransactionRepository,
        accounts: any AccountRepository,
        dataVersion: DataVersion
    ) {
        id = transaction.id
        isShared = transaction.isShared
        type = transaction.type
        category = transaction.category
        amountText = "\(transaction.amount.amount)"
        note = transaction.note
        date = transaction.date
        accountID = transaction.accountID
        self.transactions = transactions
        accountRepository = accounts
        self.dataVersion = dataVersion
    }

    /// 打開 sheet 時呼叫：載入資金帳戶(家人的資金帳戶也在裡面)。
    public func prepare() async {
        do {
            accounts = try await accountRepository.accounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 儲存;成功時回傳 `true`(sheet 關閉)並遞增資料版本。
    public func save() async -> Bool {
        errorMessage = nil
        guard let accountID else {
            errorMessage = "請先建立並選擇帳戶"
            return false
        }
        guard let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else {
            errorMessage = "請輸入有效金額"
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await transactions.update(id, with: TransactionDraft(
                accountID: accountID,
                type: type,
                category: category,
                amount: Money(amount),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                isShared: isShared
            ))
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "操作失敗" : message
            return false
        }
        dataVersion.bump()
        return true
    }
}
