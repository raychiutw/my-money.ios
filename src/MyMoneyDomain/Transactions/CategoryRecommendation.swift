import Foundation

/// 「智慧推薦」的結果:推薦哪個分類,以及它是從哪一層來的(上游 ADR-0009 的雙層推薦)。
public struct CategoryRecommendation: Hashable, Sendable {
    public enum Source: Sendable {
        /// 第一層:使用者(或家人)自己記過的備註。
        case history
        /// 第二層:內建的生活語意關鍵字詞庫。
        case lexicon
    }

    public let category: TransactionCategory
    public let source: Source

    public init(category: TransactionCategory, source: Source) {
        self.category = category
        self.source = source
    }
}

/// 近期交易的「備註 → 分類」對照,給智慧推薦的第一層用。
///
/// 照上游 `buildHistoryMemo`:略過沒有備註的交易和 4 種系統分類(信用卡還款、內部轉帳、ATM提款、公帳代墊報銷);
/// 備註去頭尾空白;同一個備註出現多次時以**日期最新的一筆**的分類為準。
/// 取多近的交易由呼叫端決定(iOS 取近 3 個月,上游 ADR-0009 寫「近 3～6 個月」)。
public struct NoteHistory: Sendable {
    struct Entry: Sendable {
        let note: String
        let category: TransactionCategory
    }

    /// 依日期由新到舊,每個備註只留最新的一筆。
    let entries: [Entry]

    public static let empty = NoteHistory(transactions: [])

    public init(transactions: [Transaction]) {
        // `sorted` 不保證穩定,自己帶 index:同一天的交易保持傳進來的順序(後端是由新到舊)。
        let ordered = transactions.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset }
            .map(\.element)
        var seen = Set<String>()
        var entries: [Entry] = []
        for transaction in ordered where !TransactionCategory.systemCategories.contains(transaction.category) {
            let note = transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty, seen.insert(note).inserted else { continue }
            entries.append(Entry(note: note, category: transaction.category))
        }
        self.entries = entries
    }
}

/// 依備註推薦分類。邏輯逐條對齊上游 `recommendCategory`(`web/src/components/utils.ts`):
///
/// 1. 備註去頭尾空白,空白不推薦。
/// 2. **歷史層**:先比對「完全相同的備註」;再依序比對「其中一個包含另一個」(不分大小寫,歷史備註至少 2 個字)。
///    命中的分類必須屬於目前類型的清單才採用,否則繼續往下找。
/// 3. **詞庫層**:依固定順序逐條比對(不分大小寫),第一個命中的規則勝出。
/// 4. 都沒命中就沒有推薦,呼叫端保留目前的分類。
///
/// 這是輸入輔助,不改後端的任何數字。
public enum CategoryRecommender {
    public static func recommend(note: String, type: TransactionType, history: NoteHistory = .empty) -> CategoryRecommendation? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let allowed = type == .expense ? TransactionCategory.expenseCategories : TransactionCategory.incomeCategories

        // 第一層:完全相同(區分大小寫,跟上游一樣)。
        if let exact = history.entries.first(where: { $0.note == trimmed }), allowed.contains(exact.category) {
            return CategoryRecommendation(category: exact.category, source: .history)
        }
        // 第一層:互相包含。長度用 UTF-16 算,跟上游 JavaScript 的 `length` 一致。
        for entry in history.entries where entry.note.utf16.count >= 2 && allowed.contains(entry.category) {
            let historyNote = entry.note.lowercased()
            if lower.contains(historyNote) || historyNote.contains(lower) {
                return CategoryRecommendation(category: entry.category, source: .history)
            }
        }

        // 第二層:詞庫。
        let rules = type == .expense ? CategoryLexicon.expense : CategoryLexicon.income
        if let rule = rules.first(where: { $0.keywords.contains(where: lower.contains) }) {
            return CategoryRecommendation(category: TransactionCategory(rule.category), source: .lexicon)
        }
        return nil
    }
}
