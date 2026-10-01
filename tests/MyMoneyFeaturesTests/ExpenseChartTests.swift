import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import Testing

@Suite("統計頁的支出分類圓餅圖:最多 8 塊、分類色固定、其餘併成灰色(DESIGN.md「顏色」,#100)")
struct ExpenseChartTests {
    private func expenses(_ pairs: [(String, Int)]) -> [CategoryExpense] {
        pairs.map { CategoryExpense(category: TransactionCategory($0.0), total: Money(Decimal($0.1))) }
    }

    /// 11 個有專屬色的分類，金額由大到小。
    private let coloredByAmount: [(String, Int)] = [
        ("餐飲", 1100), ("交通", 1000), ("汽機車輛", 900), ("居家水電", 800), ("數位訂閱", 700), ("購物", 600),
        ("生活", 500), ("娛樂", 400), ("醫療", 300), ("教育", 200), ("旅行度假", 100),
    ]

    @Test("有專屬色的分類不超過 8 種時，每種一塊，依金額由大到小，沒有灰色")
    func fewColoredCategoriesAreNotMerged() {
        let chart = ExpenseChart(expenses: expenses([("交通", 300), ("餐飲", 500), ("購物", 100)]))

        #expect(chart.slices.map(\.name) == ["餐飲", "交通", "購物"])
        #expect(chart.slices.allSatisfy { !$0.isMerged })
        #expect(!chart.slices.map(\.color).contains(.gray))
    }

    @Test("剛好 8 種有專屬色的分類時，8 塊都各自一塊，不合併")
    func eightColoredCategoriesAreNotMerged() {
        let chart = ExpenseChart(expenses: expenses(Array(coloredByAmount.prefix(8))))

        #expect(chart.slices.count == 8)
        #expect(chart.slices.allSatisfy { !$0.isMerged })
    }

    @Test("超過 8 種時，只留金額最大的 7 個有專屬色的分類，其餘併成 1 塊灰色")
    func moreThanEightKeepsTopSevenAndMergesTheRest() {
        let chart = ExpenseChart(expenses: expenses(coloredByAmount))

        #expect(chart.slices.count == 8)
        #expect(chart.slices.prefix(7).map(\.name) == ["餐飲", "交通", "汽機車輛", "居家水電", "數位訂閱", "購物", "生活"])
        let merged = chart.slices[7]
        #expect(merged.isMerged)
        #expect(merged.color == .gray)
        #expect(merged.categories.map(\.name) == ["娛樂", "醫療", "教育", "旅行度假"])
        #expect(merged.total == Money(1000))
    }

    @Test("沒有專屬色的分類(美妝保養、寵物毛孩、社交人情、保險稅費、其他，以及清單外的舊分類)永遠併入灰色")
    func categoriesWithoutDedicatedColorAreAlwaysMerged() {
        let chart = ExpenseChart(expenses: expenses([
            ("餐飲", 500), ("保險稅費", 9000), ("其他", 400), ("副業", 300), ("美妝保養", 200), ("交通", 100),
        ]))

        #expect(chart.slices.map(\.name) == ["餐飲", "交通", ExpenseChart.mergedName])
        let merged = chart.slices[2]
        #expect(merged.color == .gray)
        #expect(merged.categories.map(\.name) == ["保險稅費", "其他", "副業", "美妝保養"])
        #expect(merged.total == Money(9900))
    }

    @Test("16 種支出分類全都有支出時，圖仍是 8 塊")
    func sixteenCategoriesStayWithinEightSlices() {
        let all = TransactionCategory.expenseCategories.enumerated().map { index, category in
            CategoryExpense(category: category, total: Money(Decimal(1000 - index * 10)))
        }

        let chart = ExpenseChart(expenses: all)

        #expect(chart.slices.count <= 8)
        #expect(chart.slices.map(\.total).reduce(.zero, +) == all.map(\.total).reduce(.zero, +), "合併後金額有少")
    }

    private static let fixedColors: [(String, CategoryChartColor)] = [
        ("餐飲", CategoryChartColor.orange), ("交通", CategoryChartColor.blue), ("汽機車輛", CategoryChartColor.indigo),
        ("居家水電", CategoryChartColor.teal), ("數位訂閱", CategoryChartColor.mint), ("購物", CategoryChartColor.pink),
        ("生活", CategoryChartColor.green), ("娛樂", CategoryChartColor.purple), ("醫療", CategoryChartColor.cyan),
        ("教育", CategoryChartColor.yellow), ("旅行度假", CategoryChartColor.brown), ("美妝保養", CategoryChartColor.gray),
        ("寵物毛孩", CategoryChartColor.gray), ("社交人情", CategoryChartColor.gray), ("保險稅費", CategoryChartColor.gray),
        ("其他", CategoryChartColor.gray), ("副業", CategoryChartColor.gray),
    ]

    @Test("分類色固定:同一個分類不管排名或金額，都是同一個顏色", arguments: ExpenseChartTests.fixedColors)
    func colorIsFixedPerCategory(name: String, expected: CategoryChartColor) {
        #expect(CategoryChartColor(category: TransactionCategory(name)) == expected)

        let alone = ExpenseChart(expenses: expenses([(name, 1)]))
        let amongOthers = ExpenseChart(expenses: expenses([("餐飲", 99999), (name, 1)]))
        #expect(alone.color(for: TransactionCategory(name)) == expected)
        #expect(amongOthers.color(for: TransactionCategory(name)) == expected)
    }

    @Test("11 種專屬色彼此不同，而且不用紅色(紅色留給支出與超支)")
    func dedicatedColorsAreDistinct() {
        let dedicated = CategoryChartColor.allCases.filter { $0 != .gray }

        #expect(dedicated.count == 11)
        #expect(Set(dedicated).count == dedicated.count)
        #expect(!dedicated.map { "\($0)" }.contains("red"))
    }

    @Test("清單的圓點顏色跟圖一致:合併進灰色的分類，圓點也是灰色")
    func legendColorMatchesTheChart() {
        let chart = ExpenseChart(expenses: expenses(coloredByAmount))

        #expect(chart.color(for: TransactionCategory("餐飲")) == .orange)
        #expect(chart.color(for: TransactionCategory("教育")) == .gray)
        #expect(chart.color(for: TransactionCategory("旅行度假")) == .gray)
    }

    @Test("VoiceOver:合併的灰色塊念出它包含哪些分類，單獨的一塊念分類名稱")
    func spokenNames() {
        let chart = ExpenseChart(expenses: expenses(coloredByAmount))

        #expect(chart.slices[0].spokenName == "餐飲")
        #expect(chart.slices[7].spokenName == "其餘分類，包含 娛樂、醫療、教育、旅行度假")
    }

    @Test("同金額時順序穩定，依原本的順序")
    func ties() {
        let chart = ExpenseChart(expenses: expenses([("購物", 100), ("餐飲", 100), ("交通", 100)]))

        #expect(chart.slices.map(\.name) == ["購物", "餐飲", "交通"])
    }

    @Test("沒有支出時沒有任何一塊")
    func empty() {
        #expect(ExpenseChart(expenses: []).slices.isEmpty)
    }
}
