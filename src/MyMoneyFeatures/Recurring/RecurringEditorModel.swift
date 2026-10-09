import Foundation
import MyMoneyDomain
import Observation

/// 新增或編輯週期收支的 sheet(parity.md「週期收支」)。
@MainActor
@Observable
public final class RecurringEditorModel: Submitting {
    /// 關聯帳戶的選項(銀行存款帳戶與信用卡帳戶都可以)。
    public private(set) var accounts: [Account] = []
    public var type: TransactionType = .expense
    public var name = ""
    public var amountText = ""
    /// 切換週期時，月份超出新週期的範圍就重設為第一項(月繳一律是 1)。
    public var cycle: RecurringCycle = .monthly {
        didSet { monthOfCycle = cycle.clampedMonth(monthOfCycle) }
    }
    /// 扣款日或入帳日(1 到 31)。
    public var dayOfCycle = 1
    /// 繳費月份(`month_of_cycle`，#131):月繳沒有這個欄位(固定 1)，其他週期依 `monthOptions` 選。
    public var monthOfCycle = 1
    /// 關聯帳戶;`nil` 是「無特定帳戶」。選了帳戶就依帳戶帶入歸屬(家庭公帳的帳戶 → 家庭公帳，個人帳戶 → 個人私帳)，
    /// 選「無特定帳戶」不動歸屬;之後仍可手動改(上游 ADR 0016，跟 web 的 onChange 一致)。
    public var accountID: AccountID? {
        didSet {
            guard let accountID, let account = accounts.first(where: { $0.id == accountID }) else { return }
            isShared = account.isJointFund
        }
    }
    /// 歸屬:家庭公帳是 `true`。新增時預設隨視角(`sharedByDefault`)，編輯時是項目目前的歸屬。
    public var isShared: Bool

    public package(set) var errorMessage: String?
    public package(set) var isSaving = false

    public let title: String

    @ObservationIgnored private let editingID: RecurringItemID?
    @ObservationIgnored private let repository: any RecurringRepository
    @ObservationIgnored private let accountRepository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion

    /// 新增：預設週期支出、每月、1 號、無特定帳戶;歸屬預設隨視角:家庭公帳視角 → 家庭公帳，其他 → 個人私帳(`sharedByDefault`)。
    public init(
        adding: Void, sharedByDefault: Bool = false, repository: any RecurringRepository, accounts: any AccountRepository,
        dataVersion: DataVersion
    ) {
        title = "新增週期收支"
        editingID = nil
        isShared = sharedByDefault
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
        monthOfCycle = item.monthOfCycle
        accountID = item.accountID
        isShared = item.isShared
        self.repository = repository
        accountRepository = accounts
        self.dataVersion = dataVersion
    }

    /// 目前週期的繳費月份選項(文字照上游 web);月繳沒有，不顯示月份欄位。
    public var monthOptions: [RecurringMonthOption] {
        switch cycle {
        case .monthly: []
        case .bimonthly:
            [
                RecurringMonthOption(value: 1, title: "單數月（1、3、5、7、9、11月）"),
                RecurringMonthOption(value: 2, title: "雙數月（2、4、6、8、10、12月）"),
            ]
        case .quarterly, .semiannual:
            cycle.monthChoices.map { RecurringMonthOption(value: $0, title: "\(cycle.monthList(from: $0, separator: "、")) 月") }
        case .annual:
            cycle.monthChoices.map { RecurringMonthOption(value: $0, title: "每年 \($0) 月") }
        }
    }

    /// 月份欄位的標籤:年繳是「扣款月份／入帳月份」，雙月繳是「單數或雙數月」，其他是「起算月份」(同 web)。
    public var monthTitle: String {
        switch cycle {
        case .annual: type == .expense ? "扣款月份" : "入帳月份"
        case .bimonthly: "單數或雙數月"
        default: "起算月份"
        }
    }

    /// 打開 sheet 時呼叫：載入資產帳戶。新增時關聯帳戶是「無特定帳戶」,不預選第一個
    /// (上游 ADR 0011:週期收支的關聯帳戶是選填;使用者在帳戶載入之前就選了的話，保留他的選擇)。
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
            name: trimmedName, type: type, amount: amount, cycle: cycle, dayOfCycle: dayOfCycle,
            monthOfCycle: cycle.clampedMonth(monthOfCycle), accountID: accountID, isShared: isShared
        )
        guard await submitting(failure: "儲存失敗", {
            if let editingID {
                try await repository.update(editingID, with: draft)
            } else {
                try await repository.create(draft)
            }
        }) != nil else { return false }
        dataVersion.bump()
        return true
    }
}

/// 繳費月份的一個選項(#131)。
public struct RecurringMonthOption: Identifiable, Hashable, Sendable {
    public let value: Int
    public let title: String

    public var id: Int { value }
}
