import Foundation
import MyMoneyDomain
import Observation

/// 「記一筆」sheet(parity.md「總覽」的記一筆)。每個 session 一份，讓下一筆沿用上一筆的選擇。
@MainActor
@Observable
public final class QuickEntryModel {
    public private(set) var accounts: [Account] = []

    public let title = "記一筆"

    /// 家庭公帳(預設)或個人私帳。
    public var isShared = true

    /// 切到支出時分類重設為「餐飲」,切到收入時重設為「薪資」(跟 web 一樣);依備註推薦的提示跟著清掉。
    public var type: TransactionType = .expense {
        didSet {
            guard type != oldValue else { return }
            category = type == .expense ? .dining : .salary
            recommendation = nil
        }
    }

    public var category: TransactionCategory = .dining
    public var amountText = ""

    /// 備註。還沒手動選過分類時，每次改動都依備註推薦分類(`preselectCategory`)。
    public var note = "" {
        didSet {
            guard note != oldValue else { return }
            preselectCategory()
        }
    }

    /// 目前分類是依備註自動預選的結果;使用者手動選分類、切換類型或沒有命中時是 `nil`。
    public private(set) var recommendation: CategoryRecommendation?

    /// 分類旁邊的提示文字:歷史命中是「依歷史習慣推薦【分類】」,詞庫命中是「智慧推薦為【分類】」。
    public var categoryHintText: String? { recommendation?.hintText }

    /// 使用者這次打開之後手動選過分類:鎖定，之後不論備註怎麼改，都不再覆蓋他的選擇。
    public private(set) var isCategoryChosen = false
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
    /// 近 3 個月的備註歷史，給智慧推薦的第一層用;還沒載入或載入失敗時是空的。
    @ObservationIgnored private var noteHistory = NoteHistory.empty

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

    /// 打開 sheet 時呼叫：載入資產帳戶;還沒選過、或選的帳戶已經不在時，預設第一個。
    /// 每次打開都從沒鎖定分類、沒有推薦提示開始。
    public func prepare() async {
        isCategoryChosen = false
        recommendation = nil
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

    /// 使用者手動選分類:鎖定，之後備註怎麼改都不再覆蓋，提示也清掉。
    public func chooseCategory(_ category: TransactionCategory) {
        self.category = category
        isCategoryChosen = true
        recommendation = nil
    }

    /// 載入近 3 個月的備註當歷史(智慧推薦的第一層)。失敗或很慢都不擋記帳:沒有歷史就只走詞庫。
    /// 載完時如果已經有備註、而且還沒手動選過分類，照新的歷史重新推薦一次。
    public func loadNoteHistory() async {
        let end = today()
        do {
            let recent = try await transactions.allTransactions(from: end.addingMonths(-3), to: end, scope: .all)
            noteHistory = NoteHistory(transactions: recent)
        } catch {
            noteHistory = .empty
        }
        preselectCategory()
    }

    /// 備註變更時依備註推薦分類(還沒手動選過才做):有結果就改分類並記下來源;沒結果就清掉提示，分類不動。
    private func preselectCategory() {
        guard !isCategoryChosen else { return }
        guard let result = CategoryRecommender.recommend(note: note, type: type, history: noteHistory) else {
            recommendation = nil
            return
        }
        category = result.category
        recommendation = result
    }

    /// 送出;成功時回傳 `true`(sheet 關閉)。只清空金額、備註和日期，其他選擇保留給下一筆。
    public func save() async -> Bool {
        errorMessage = nil
        guard let accountID, !accounts.isEmpty else {
            errorMessage = "請先至「帳戶」建立至少一個帳戶"
            return false
        }
        guard let amount = Money(wholeNumber: amountText), amount > .zero else {
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
                amount: amount,
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

extension CategoryRecommendation {
    /// 「依歷史習慣推薦【餐飲】」「智慧推薦為【汽機車輛】」(上游 97f4789 的提示文字,前面的圖示由畫面放 SF Symbol)。
    public var hintText: String {
        switch source {
        case .history: "依歷史習慣推薦【\(category.name)】"
        case .lexicon: "智慧推薦為【\(category.name)】"
        }
    }
}
