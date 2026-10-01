import Foundation
import MyMoneyDomain
import Testing

@Suite("智慧推薦:依備註預選分類(上游 ADR-0009 的雙層推薦)")
struct CategoryRecommenderTests {
    private func recommend(_ note: String, _ type: TransactionType = .expense, history: NoteHistory = .empty) -> CategoryRecommendation? {
        CategoryRecommender.recommend(note: note, type: type, history: history)
    }

    private func history(_ pairs: [(String, String)], type: TransactionType = .expense) -> NoteHistory {
        let transactions = pairs.enumerated().map { index, pair in
            Transaction(
                id: TransactionID("h\(index)"), accountID: AccountID("a"), accountName: nil, type: type,
                category: TransactionCategory(pair.1), amount: Money(100), note: pair.0,
                date: CalendarDay(year: 2026, month: 9, day: 28 - index), isShared: true, recorderName: nil
            )
        }
        return NoteHistory(transactions: transactions)
    }

    // MARK: - 詞庫層(第二層)

    @Test("支出的詞庫:常見備註對到對應的分類", arguments: [
        ("中油加油", "汽機車輛"), ("Netflix", "數位訂閱"), ("房租", "居家水電"), ("剪髮", "美妝保養"), ("貓砂", "寵物毛孩"),
        ("機票", "旅行度假"), ("保費", "保險稅費"), ("全聯", "生活"), ("捷運", "交通"), ("午餐", "餐飲"),
    ])
    func expenseLexicon(note: String, category: String) {
        let recommendation = recommend(note)

        #expect(recommendation?.category.name == category)
        #expect(recommendation?.source == .lexicon)
    }

    @Test("收入的詞庫:支出與收入各用各的分類清單", arguments: [
        ("育兒津貼", "政府補貼"), ("壓歲錢", "禮金餽贈"), ("二手拍賣", "二手出清"), ("薪水", "薪資"),
        ("年終", "獎金"), ("股息", "投資"), ("接案", "兼職"),
    ])
    func incomeLexicon(note: String, category: String) {
        #expect(recommend(note, .income)?.category.name == category)
    }

    @Test("規則的順序決定誰先命中:Netflix 的「net」不會被購物搶走，單字「早」算餐飲")
    func ruleOrderDecidesTheWinner() {
        #expect(recommend("Netflix 月費")?.category.name == "數位訂閱")
        #expect(recommend("早")?.category.name == "餐飲")
        // 備註同時含兩條規則的關鍵字時，先排的規則勝出(汽機車輛在餐飲之前)。
        #expect(recommend("加油站買咖啡")?.category.name == "汽機車輛")
    }

    @Test("備註前後的空白不算，大小寫不分；空白或沒有命中時沒有推薦")
    func trimmingCaseAndNoMatch() {
        #expect(recommend("  NETFLIX  ")?.category.name == "數位訂閱")
        #expect(recommend("") == nil)
        #expect(recommend("   ") == nil)
        #expect(recommend("zzz") == nil)
    }

    @Test("推薦的分類一定在目前類型的清單裡，不會把收入備註推薦成支出分類")
    func recommendationBelongsToTheType() {
        for note in ["中油加油", "薪水", "育兒津貼", "午餐", "壓歲錢"] {
            if let expense = recommend(note, .expense) {
                #expect(TransactionCategory.expenseCategories.contains(expense.category), "支出 \(note) → \(expense.category.name)")
            }
            if let income = recommend(note, .income) {
                #expect(TransactionCategory.incomeCategories.contains(income.category), "收入 \(note) → \(income.category.name)")
            }
        }
    }

    @Test("詞庫跟上游逐筆一致:上游的 recommendCategory 在 1,500 多個備註上的結果(scripts/sync-category-lexicon.mjs 產生)")
    func matchesUpstreamGoldenTable() {
        var mismatches: [String] = []
        var count = 0
        for line in CategoryLexiconGolden.table.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3 else {
                mismatches.append("格式不對:\(line)")
                continue
            }
            let type: TransactionType = parts[0] == "income" ? .income : .expense
            let actual = recommend(parts[1], type)?.category.name ?? ""
            count += 1
            if actual != parts[2] {
                mismatches.append("\(parts[0]) 「\(parts[1])」 上游 \(parts[2].isEmpty ? "無" : parts[2]) / iOS \(actual.isEmpty ? "無" : actual)")
            }
        }
        #expect(count > 1_000)
        #expect(mismatches.isEmpty, "\(mismatches.count) 筆和上游不同:\(mismatches.prefix(10))")
    }

    // MARK: - 歷史層(第一層)

    @Test("歷史完全相同的備註:採用當時選的分類，來源是歷史")
    func exactHistoryMatch() {
        let recommendation = recommend("全聯", history: history([("全聯", "餐飲")]))

        #expect(recommendation?.category.name == "餐飲", "詞庫會推薦生活，但歷史優先")
        #expect(recommendation?.source == .history)
    }

    @Test("歷史包含:備註包含歷史備註，或被歷史備註包含(歷史備註至少 2 個字)，不分大小寫", arguments: [
        ("中油加油站", "中油", "餐飲"), ("中油", "中油加油站", "餐飲"), ("NETFLIX月費", "netflix", "生活"),
    ])
    func containmentHistoryMatch(note: String, historyNote: String, category: String) {
        let recommendation = recommend(note, history: history([(historyNote, category)]))

        #expect(recommendation?.category.name == category)
        #expect(recommendation?.source == .history)
    }

    @Test("歷史備註只有 1 個字時不算包含(相同才算)，改走詞庫")
    func oneCharacterHistoryDoesNotMatchByContainment() {
        let recommendation = recommend("中油加油", history: history([("中", "教育")]))

        #expect(recommendation?.category.name == "汽機車輛")
        #expect(recommendation?.source == .lexicon)
    }

    @Test("同一個備註記過好幾次，以最新一筆的分類為準")
    func newestEntryWins() {
        // history() 讓 index 越小日期越新。
        let recommendation = recommend("午餐", history: history([("午餐", "娛樂"), ("午餐", "醫療")]))

        #expect(recommendation?.category.name == "娛樂")
    }

    @Test("歷史的日期不是由新到舊時，也以日期最新的一筆為準")
    func newestEntryWinsRegardlessOfInputOrder() {
        func entry(_ id: String, _ day: Int, _ category: String) -> Transaction {
            Transaction(
                id: TransactionID(id), accountID: AccountID("a"), accountName: nil, type: .expense,
                category: TransactionCategory(category), amount: Money(1), note: "午餐",
                date: CalendarDay(year: 2026, month: 9, day: day), isShared: true, recorderName: nil
            )
        }
        let older = entry("old", 1, "醫療")
        let newer = entry("new", 20, "娛樂")

        #expect(recommend("午餐", history: NoteHistory(transactions: [older, newer]))?.category.name == "娛樂")
        #expect(recommend("午餐", history: NoteHistory(transactions: [newer, older]))?.category.name == "娛樂")
    }

    @Test("系統分類的交易不進歷史，也不把清單外的分類推薦出來")
    func systemAndUnknownCategoriesAreIgnored() {
        // 系統分類不進歷史 → 備註「中油」改走詞庫。
        let system = history([("中油", "信用卡還款")])
        #expect(recommend("中油", history: system)?.source == .lexicon)
        // 歷史的分類不在目前類型的清單(舊分類「副業」)→ 忽略，繼續往下找，最後走詞庫。
        let legacy = history([("中油", "副業")])
        let recommendation = recommend("中油", history: legacy)
        #expect(recommendation?.category.name == "汽機車輛")
        #expect(recommendation?.source == .lexicon)
    }

    @Test("歷史的分類不屬於目前的類型時不採用:收入備註不會被支出歷史影響")
    func historyOfTheOtherTypeIsNotUsed() {
        let expenseHistory = history([("薪水", "餐飲")])

        #expect(recommend("薪水", .income, history: expenseHistory)?.category.name == "薪資")
    }

    @Test("完全相同的歷史比包含優先；完全相同但分類不在清單時，繼續找包含的")
    func exactBeforeContainmentAndFallThrough() {
        let both = history([("午餐便當", "教育"), ("午餐", "醫療")])
        // 「午餐」完全相同 → 醫療;不是先碰到的「午餐便當」。
        #expect(recommend("午餐", history: both)?.category.name == "醫療")

        let exactButUnknown = history([("午餐", "副業"), ("午餐便當", "教育")])
        #expect(recommend("午餐", history: exactButUnknown)?.category.name == "教育")
    }
}

@Suite("日期加減月份(歷史只取近 3 個月)")
struct CalendarDayMonthsTests {
    @Test("往前 3 個月", arguments: [
        (CalendarDay(year: 2026, month: 9, day: 28), CalendarDay(year: 2026, month: 6, day: 28)),
        (CalendarDay(year: 2026, month: 2, day: 10), CalendarDay(year: 2025, month: 11, day: 10)),
        (CalendarDay(year: 2026, month: 5, day: 31), CalendarDay(year: 2026, month: 2, day: 28)),
        (CalendarDay(year: 2024, month: 5, day: 31), CalendarDay(year: 2024, month: 2, day: 29)),
        (CalendarDay(year: 2026, month: 3, day: 31), CalendarDay(year: 2025, month: 12, day: 31)),
    ])
    func threeMonthsBack(day: CalendarDay, expected: CalendarDay) {
        #expect(day.addingMonths(-3) == expected)
    }
}
