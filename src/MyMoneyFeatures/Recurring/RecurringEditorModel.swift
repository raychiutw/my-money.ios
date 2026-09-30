import Foundation
import MyMoneyDomain
import Observation

/// 新增或編輯週期收支的 sheet(parity.md「週期收支」)。
@MainActor
@Observable
public final class RecurringEditorModel {
    /// 關聯帳戶的選項(銀行存款帳戶與信用卡帳戶都可以)。
    public private(set) var accounts: [Account] = []
    public var type: TransactionType = .expense
    public var name = ""
    public var amountText = ""
    public var cycle: RecurringCycle = .monthly
    /// 扣款日或入帳日(1 到 31)。
    public var dayOfCycle = 1
    /// 關聯帳戶;`nil` 是「無特定帳戶」。
    public var accountID: AccountID?

    public private(set) var errorMessage: String?
    public private(set) var isSaving = false

    public let title: String

    @ObservationIgnored private let editingID: RecurringItemID?
    @ObservationIgnored private let repository: any RecurringRepository
    @ObservationIgnored private let accountRepository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion

    /// 新增：預設週期支出、每月、1 號，關聯帳戶是第一個資產帳戶(在 `prepare()` 帶入)。
    public init(adding: Void, repository: any RecurringRepository, accounts: any AccountRepository, dataVersion: DataVersion) {
        title = "新增週期收支"
        editingID = nil
        self.repository = repository
        accountRepository = accounts
        self.dataVersion = dataVersion
    }

    public init(editing item: RecurringItem, repository: any RecurringRepository, accounts: any AccountRepository, dataVersion: DataVersion) {
        title = "編輯週期收支"
        editingID = item.id
        type = item.type
        name = item.name
        amountText = "\(item.amount.amount)"
        cycle = item.cycle
        dayOfCycle = item.dayOfCycle
        accountID = item.accountID
        self.repository = repository
        accountRepository = accounts
        self.dataVersion = dataVersion
    }

    /// 打開 sheet 時呼叫：載入資產帳戶;新增時帶入第一個。
    public func prepare() async {
        do {
            accounts = try await accountRepository.accounts()
            // 使用者在資產帳戶載入之前就選了，保留他的選擇。
            if editingID == nil, accountID == nil { accountID = accounts.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 儲存;成功時回傳 `true`(sheet 關閉)並遞增資料版本。
    public func save() async -> Bool {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "請填寫項目名稱"
            return false
        }
        guard let amount = Money(wholeNumber: amountText), amount > .zero else {
            errorMessage = "請輸入有效金額"
            return false
        }
        let draft = RecurringDraft(
            name: trimmedName, type: type, amount: amount, cycle: cycle, dayOfCycle: dayOfCycle, accountID: accountID
        )
        isSaving = true
        defer { isSaving = false }
        do {
            if let editingID {
                try await repository.update(editingID, with: draft)
            } else {
                try await repository.create(draft)
            }
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? "儲存失敗" : message
            return false
        }
        dataVersion.bump()
        return true
    }
}
