import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("統計與預算")
struct StatisticsTests {
    private let september = CalendarMonth(year: 2026, month: 9)

    private func loaded(
        _ repository: InMemoryStatisticsRepository? = nil,
        scope: ViewScope = .all,
        dataVersion: DataVersion = DataVersion()
    ) async -> (StatisticsModel, InMemoryStatisticsRepository) {
        let repository = repository ?? InMemoryStatisticsRepository.sample(month: september)
        let model = StatisticsModel(
            repository: repository, dataVersion: dataVersion, today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )
        model.scope = scope
        await model.load()
        return (model, repository)
    }

    private func share(_ name: String, _ total: Int) -> HouseholdShare {
        HouseholdShare(userID: UserID(name), userName: name, total: Money(Decimal(total)))
    }

    @Test("月份預設本月(台灣時間),視角預設全部")
    func defaults() {
        let model = StatisticsModel(
            repository: InMemoryStatisticsRepository.sample(month: september), dataVersion: DataVersion(),
            today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )

        #expect(model.month == september)
        #expect(model.scope == .all)
    }

    /// 系統依地區的格式(DESIGN.md「日期」),跟 DatePicker 的「2026年9月29日」一致，不再是「2026 年 9 月」。
    @Test("月份與年份用系統格式：「2026年9月」「2026年」;預算額度 sheet 也一樣")
    func monthAndYearTitles() async throws {
        let model = StatisticsModel(
            repository: InMemoryStatisticsRepository.sample(month: september), dataVersion: DataVersion(),
            locale: Locale(identifier: "zh_Hant_TW"), today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )
        await model.load()

        #expect(model.monthTitle == "2026年9月")
        #expect(model.yearTitle == "2026年")
        #expect(model.makeBudgetEditor(for: .dining).monthTitle == "2026年9月")

        model.month = CalendarMonth(year: 2027, month: 1)
        #expect(model.monthTitle == "2027年1月")
        #expect(model.yearTitle == "2027年")
    }

    /// web 的收支趨勢永遠是今年(parity 刻意偏離第 12 項)。
    @Test("依所選的月份與視角查詢;收支趨勢帶入所選月份的年份;已花另外用我記的支出")
    func queries() async {
        let repository = InMemoryStatisticsRepository.sample(month: september)
        let model = StatisticsModel(
            repository: repository, dataVersion: DataVersion(), today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )
        model.month = CalendarMonth(year: 2025, month: 12)
        model.scope = .household

        await model.load()

        let december = CalendarMonth(year: 2025, month: 12)
        // 兩個分類支出的查詢同時送出，順序不固定。
        #expect(Set(await repository.categoryQueries) == [.init(month: december, scope: .household), .init(month: december, scope: .personal)])
        #expect(await repository.monthlyQueries == [.init(year: 2025, scope: .household)])
        #expect(await repository.shareQueries == [december])
        #expect(await repository.budgetQueries == [december])
    }

    @Test("支出分類的合計")
    func categoryTotal() async {
        let (model, _) = await loaded()

        #expect(model.categoryExpenses.map(\.category.name) == ["購物", "交通", "餐飲"])
        #expect(model.totalCategoryExpense == Money(1250))
    }

    /// web 一次列出 8 個支出分類(parity 刻意偏離第 50 項)。
    @Test("預算額度只列有預算或本月有支出(已花)的分類，依支出分類的固定順序")
    func budgetRowsListBudgetedOrSpentCategories() async {
        let (model, _) = await loaded()

        #expect(model.budgetRows.map(\.category.name) == ["餐飲", "交通", "購物"])
    }

    /// 本月有支出指的是已花(我記的支出),不隨視角改變：家人記的家庭公帳支出不會多列一個分類。
    @Test("有預算但還沒花的分類、沒有預算但有已花的分類都列出;只有家人花的分類不列")
    func budgetRowsIncludeBudgetOnlyAndSpentOnly() async {
        let repository = InMemoryStatisticsRepository(
            expensesByScope: [
                .personal: [CategoryExpense(category: TransactionCategory("醫療"), total: Money(300))],
                .household: [CategoryExpense(category: TransactionCategory("生活"), total: Money(2000))],
            ],
            summaries: [],
            shares: [],
            budgets: [Budget(category: TransactionCategory("教育"), amount: Money(500), spent: .zero, isOver: false)]
        )

        let (model, _) = await loaded(repository, scope: .household)

        #expect(model.budgetRows.map(\.category.name) == ["醫療", "教育"])
    }

    @Test("「新增預算額度」選單列出其餘的支出分類，依固定順序")
    func addBudgetMenuListsRemainingCategories() async {
        let (model, _) = await loaded()

        #expect(model.addableBudgetCategories.map(\.name) == [
            "汽機車輛", "居家水電", "數位訂閱", "生活", "娛樂", "美妝保養", "醫療", "教育",
            "寵物毛孩", "旅行度假", "社交人情", "保險稅費", "其他",
        ])
    }

    @Test("全部分類都有預算時沒有「新增預算額度」選單")
    func noAddBudgetMenuWhenEveryCategoryHasBudget() async {
        let repository = InMemoryStatisticsRepository(
            expensesByScope: [:],
            summaries: [],
            shares: [],
            budgets: TransactionCategory.expenseCategories.map {
                Budget(category: $0, amount: Money(1000), spent: .zero, isOver: false)
            }
        )

        let (model, _) = await loaded(repository)

        #expect(model.budgetRows.map(\.category) == TransactionCategory.expenseCategories)
        #expect(model.addableBudgetCategories.isEmpty)
    }

    @Test("點整列和從選單選分類打開同一個設定 sheet:已有預算帶入原值，沒有時預設 5000")
    func budgetEditorFromRowOrMenu() async {
        let (model, _) = await loaded()

        let fromMenu = model.makeBudgetEditor(for: TransactionCategory("娛樂"))
        #expect(fromMenu.title == "設定 娛樂 的預算")
        #expect(fromMenu.amountText == "5000")
        #expect(model.makeBudgetEditor(for: .dining).amountText == "100")
    }

    /// web 的統計頁用視角的分類支出當已花(parity 刻意偏離第 10 項)。
    @Test("已花一律是我記的支出，不隨視角改變：有預算時用後端的 spent,沒有預算時用個人視角的分類支出")
    func spentIgnoresScope() async throws {
        let (model, _) = await loaded(scope: .household)
        let rows = Dictionary(uniqueKeysWithValues: model.budgetRows.map { ($0.category.name, $0) })

        // 家庭視角的分類支出沒有購物，但已花仍然是我記的 880。
        #expect(rows["購物"]?.spent == Money(880))
        #expect(rows["交通"]?.spent == Money(250))
    }

    @Test("超支、接近上限(80% 以上)與沒有預算", arguments: [
        ("餐飲", BudgetRow.Status.over(by: Money(20))),
        ("購物", .nearLimit),
        ("交通", .unset),
    ])
    func budgetStatus(category: String, expected: BudgetRow.Status) async throws {
        let (model, _) = await loaded()
        let row = try #require(model.budgetRows.first { $0.category.name == category })

        #expect(row.status == expected)
    }

    @Test("已花未達 80% 時是正常", arguments: [(7999, BudgetRow.Status.normal), (8000, .nearLimit), (10000, .nearLimit)])
    func nearLimitThreshold(spent: Int, expected: BudgetRow.Status) {
        let row = BudgetRow(
            category: .dining,
            budget: Budget(category: .dining, amount: Money(10000), spent: Money(Decimal(spent)), isOver: false),
            fallbackSpent: .zero
        )

        #expect(row.status == expected)
    }

    @Test("公帳代墊款只在家庭或全部視角、而且有資料時顯示", arguments: [
        (ViewScope.all, true), (.household, true), (.personal, false),
    ])
    func householdSharesVisibility(scope: ViewScope, visible: Bool) async {
        let (model, _) = await loaded(scope: scope)

        #expect(model.showsHouseholdShares == visible)
    }

    @Test("沒有公帳代墊款時不顯示")
    func householdSharesHiddenWithoutData() async {
        let (model, _) = await loaded(InMemoryStatisticsRepository.sample(month: september, shares: []))

        #expect(!model.showsHouseholdShares)
    }

    @Test("當月家庭公帳總額與每人的佔比(1 位小數)")
    func householdShareRatios() async {
        let (model, _) = await loaded()

        #expect(model.householdTotal == Money(10000))
        #expect(model.householdShares.map(model.ratioText) == ["60.0%", "40.0%"])
    }

    @Test("剛好兩人：6,000 對 4,000,每人應負擔 5,000,少付的轉 1,000 給多付的")
    func settlementForTwo() {
        let settlement = StatisticsModel.settlement(for: [share("小明", 6000), share("小美", 4000)])

        #expect(settlement == Settlement(perPerson: Money(5000), transfer: .init(from: "小美", to: "小明", amount: Money(1000))))
    }

    @Test("兩人的公帳代墊款一樣多時不用轉帳;不是剛好兩人時沒有分攤建議")
    func settlementEdgeCases() {
        #expect(StatisticsModel.settlement(for: [share("小明", 3000), share("小美", 3000)])
            == Settlement(perPerson: Money(3000), transfer: nil))
        #expect(StatisticsModel.settlement(for: [share("小明", 3000)]) == nil)
        #expect(StatisticsModel.settlement(for: [share("小明", 3000), share("小美", 2000), share("阿公", 1000)]) == nil)
    }

    @Test("應負擔與轉帳金額四捨五入到整數")
    func settlementRounding() {
        let settlement = StatisticsModel.settlement(for: [share("小明", 1001), share("小美", 0)])

        #expect(settlement == Settlement(perPerson: Money(501), transfer: .init(from: "小美", to: "小明", amount: Money(501))))
    }

    @Test("資料版本改變後重抓")
    func refreshesOnDataVersionChange() async {
        let dataVersion = DataVersion()
        let (model, repository) = await loaded(dataVersion: dataVersion)
        let fetches = await repository.budgetQueries.count

        await model.refreshIfStale()
        #expect(await repository.budgetQueries.count == fetches)

        dataVersion.bump()
        await model.refreshIfStale()
        #expect(await repository.budgetQueries.count > fetches)
    }
}

@MainActor
@Suite("設定預算額度")
struct BudgetEditorTests {
    private let september = CalendarMonth(year: 2026, month: 9)

    private func editor(for category: TransactionCategory) async throws -> (BudgetEditorModel, InMemoryStatisticsRepository, DataVersion) {
        let repository = InMemoryStatisticsRepository.sample(month: september)
        let dataVersion = DataVersion()
        let model = StatisticsModel(
            repository: repository, dataVersion: dataVersion, today: { CalendarDay(year: 2026, month: 9, day: 28) }
        )
        await model.load()
        return (model.makeBudgetEditor(for: category), repository, dataVersion)
    }

    @Test("已有預算時帶入原值，沒有時預設 5000")
    func defaults() async throws {
        #expect(try await editor(for: .dining).0.amountText == "100")
        #expect(try await editor(for: TransactionCategory("交通")).0.amountText == "5000")
    }

    @Test("標題跟著選的分類改變;可選的是 8 個支出分類")
    func title() async throws {
        let (editor, _, _) = try await editor(for: .dining)

        #expect(editor.title == "設定 餐飲 的預算")
        editor.category = TransactionCategory("購物")
        #expect(editor.title == "設定 購物 的預算")
        #expect(BudgetEditorModel.categories == TransactionCategory.expenseCategories)
    }

    /// web 的 `step` 會擋掉合法金額(parity 刻意偏離第 4 項),iOS 接受任何正整數。
    @Test("金額要是正數", arguments: ["", "0", "-100", "abc", "1,000", "12.5"])
    func amountMustBePositive(amount: String) async throws {
        let (editor, repository, _) = try await editor(for: .dining)
        editor.amountText = amount

        #expect(!(await editor.save()))

        #expect(editor.errorMessage == "請輸入有效預算金額")
        #expect(await repository.setBudgets.isEmpty)
    }

    @Test("儲存 PUT 所選分類與月份的預算，成功後資料版本遞增")
    func save() async throws {
        let (editor, repository, dataVersion) = try await editor(for: .dining)
        editor.category = TransactionCategory("交通")
        editor.amountText = "3333"

        #expect(await editor.save())

        #expect(await repository.setBudgets == [.init(category: TransactionCategory("交通"), amount: Money(3333), month: september)])
        #expect(dataVersion.value == 1)
    }
}
