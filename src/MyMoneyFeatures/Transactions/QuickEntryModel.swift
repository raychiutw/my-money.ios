import Foundation
import MyMoneyDomain
import Observation

/// 「記一筆」sheet(parity.md「總覽」的記一筆)。每個 session 一份，讓下一筆沿用上一筆的選擇。
@MainActor
@Observable
public final class QuickEntryModel {
    public private(set) var accounts: [Account] = []

    /// 家庭公帳(預設)或個人私帳。
    public var isShared = true

    /// 切到支出時分類重設為「餐飲」,切到收入時重設為「薪資」(跟 web 一樣)。
    public var type: TransactionType = .expense {
        didSet {
            guard type != oldValue else { return }
            category = type == .expense ? .dining : .salary
        }
    }

    public var category: TransactionCategory = .dining
    public var amountText = ""
    public var note = ""
    public var date: CalendarDay
    public var accountID: AccountID?

    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    public var categories: [TransactionCategory] {
        type == .expense ? TransactionCategory.expenseCategories : TransactionCategory.incomeCategories
    }

    @ObservationIgnored private let transactions: any TransactionRepository
    @ObservationIgnored private let accountRepository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay

    public init(
        transactions: any TransactionRepository,
        accounts: any AccountRepository,
        dataVersion: DataVersion,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.transactions = transactions
        accountRepository = accounts
        self.dataVersion = dataVersion
        self.today = today
        date = today()
    }

    /// 打開 sheet 時呼叫：載入資金帳戶;還沒選過、或選的帳戶已經不在時，預設第一個。
    public func prepare() async {
        errorMessage = nil
        do {
            accounts = try await accountRepository.accounts()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if accountID == nil || !accounts.contains(where: { $0.id == accountID }) {
            accountID = accounts.first?.id
        }
    }

    /// 送出;成功時回傳 `true`(sheet 關閉)。只清空金額、備註和日期，其他選擇保留給下一筆。
    public func save() async -> Bool {
        errorMessage = nil
        guard let accountID, !accounts.isEmpty else {
            errorMessage = "請先至「帳戶」建立至少一個帳戶"
            return false
        }
        guard let amount = Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else {
            errorMessage = "請輸入正確的金額"
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await transactions.create(TransactionDraft(
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
            errorMessage = message.isEmpty ? "記帳失敗" : message
            return false
        }
        dataVersion.bump()
        amountText = ""
        note = ""
        date = today()
        return true
    }
}
