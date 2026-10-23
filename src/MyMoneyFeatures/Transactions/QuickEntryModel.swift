import Foundation
import MyMoneyDomain
import Observation

/// 「記一筆」sheet(parity.md「總覽」的記一筆)。每個 session 一份，讓下一筆沿用上一筆的選擇。
@MainActor
@Observable
public final class QuickEntryModel: Submitting {
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
    public var accountID: AccountID? {
        didSet {
            // 切到非信用卡的帳戶:「列入下期帳單」收起並重設(上游 ADR 0020)。
            if !isCreditCardSelected { defersToNextStatement = false }
        }
    }

    /// 列入下期帳單(商家延遲請款、跨結帳日刷卡或跨期退款);只有選了信用卡才有，預設不勾。
    public var defersToNextStatement = false

    public var isCreditCardSelected: Bool {
        accounts.first { $0.id == accountID }?.kind == .creditCard
    }

    public package(set) var errorMessage: String?
    public package(set) var isSaving = false

    public var categories: [TransactionCategory] {
        type == .expense ? TransactionCategory.expenseCategories : TransactionCategory.incomeCategories
    }

    @ObservationIgnored private let transactions: any TransactionRepository
    @ObservationIgnored private let accountRepository: any AccountRepository
    @ObservationIgnored private let dataVersion: DataVersion
    @ObservationIgnored private let today: () -> CalendarDay
    /// 記住上次選的帳戶(#273);`nil` 是不記(帳戶永遠從空白開始)。
    @ObservationIgnored private let accountMemory: AccountMemory?
    /// 近 3 個月的備註歷史，給智慧推薦的第一層用;還沒載入或載入失敗時是空的。
    @ObservationIgnored private var noteHistory = NoteHistory.empty
    /// 這一次打開是否已經帶入過記憶(`prepare` 會因為從帳戶清單頁返回而再跑，不能把使用者清掉的選擇又補回來)。
    @ObservationIgnored private var hasRecalled = false

    public init(
        transactions: any TransactionRepository,
        accounts: any AccountRepository,
        dataVersion: DataVersion,
        accountMemory: AccountMemory? = nil,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.transactions = transactions
        accountRepository = accounts
        self.dataVersion = dataVersion
        self.accountMemory = accountMemory
        self.today = today
        date = today()
    }

    /// 開始新的一筆(sheet 打開的那一次):帳戶是空的,不擅自預選(上游 ADR 0011「顯式帳戶選取」，#109);
    /// 唯一的例外是使用者自己上次送出時選的帳戶(#273,刻意偏離,見 `AccountMemory`)，仍可改選;也從沒鎖定分類、沒有推薦提示開始。
    ///
    /// 跟 `prepare` 分開:表單的 `.task` 在從帳戶清單頁返回時會再跑一次 `prepare`,不能因此清掉剛選的帳戶與分類的鎖定。
    public func startNewEntry() {
        isCategoryChosen = false
        recommendation = nil
        accountID = accountMemory?.recall(among: accounts)
        hasRecalled = !accounts.isEmpty
    }

    /// 載入資產帳戶(表單出現時呼叫，可以重複呼叫);已選的帳戶不在清單裡了才清掉。不預選任何帳戶。
    public func prepare() async {
        errorMessage = nil
        var loaded = true
        do {
            accounts = try await accountRepository.accounts()
        } catch {
            errorMessage = error.localizedDescription
            loaded = false
        }
        if let accountID, !accounts.contains(where: { $0.id == accountID }) {
            self.accountID = nil
        }
        // 開 sheet 時帳戶清單可能還沒載好:載好之後補帶入上次的帳戶(使用者還沒選時才補)。
        if accountID == nil, !hasRecalled { accountID = accountMemory?.recall(among: accounts) }
        // 載入失敗時還不算帶入過:重試成功再帶入。
        if loaded { hasRecalled = true }
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

    /// 送出;成功時回傳 `true`(sheet 關閉)。清空金額、備註、日期和帳戶，類型、分類、歸屬保留給下一筆。
    public func save() async -> Bool {
        errorMessage = nil
        guard !accounts.isEmpty else {
            errorMessage = "請先至「帳戶」建立至少一個帳戶"
            return false
        }
        guard let accountID else {
            errorMessage = "請選擇扣款或存入帳戶"
            return false
        }
        guard let amount = positiveAmount(amountText, label: "金額") else { return false }
        guard await submitting(failure: "記帳失敗", {
            try await transactions.create(TransactionDraft(
                accountID: accountID,
                type: type,
                category: category,
                amount: amount,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                date: date,
                isShared: isShared,
                defersToNextStatement: isCreditCardSelected && defersToNextStatement
            ))
        }) != nil else { return false }
        dataVersion.bump()
        accountMemory?.remember(accountID)
        amountText = ""
        note = ""
        date = today()
        // 帳戶不直接沿用在表單上:下一次打開由 `startNewEntry` 依記憶帶入;延期勾選不沿用。
        self.accountID = nil
        hasRecalled = false
        defersToNextStatement = false
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
