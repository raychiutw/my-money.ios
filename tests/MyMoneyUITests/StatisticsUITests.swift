import XCTest

/// 「統計」tab。資料來自 MyMoneyTestSupport 的 `InMemoryStatisticsRepository.sampleForToday()`(不連網路)。
final class StatisticsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 公帳代墊款與分攤建議;從 toolbar 的篩選按鈕切到個人視角時不顯示，按鈕的 VoiceOver 值跟著變(#63);超支標示。
    @MainActor
    func testHouseholdSharesScopeAndOverBudget() throws {
        let app = launchSignedIn()

        app.tabBars.buttons["統計"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "當月家庭公帳總額 10,000 元").waitForExistence(timeout: 5), "沒有看到公帳代墊款")
        XCTAssertTrue(element(in: app, labelContaining: "小美 轉 1,000 元 給 小明").exists, "沒有分攤建議")
        // 最上面是超大的當月支出(#120):標題帶月份，數字比一般金額列大很多，位置在公帳代墊款上面。
        let hero = app.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", "月支出")).firstMatch
        XCTAssertTrue(hero.exists, "沒有當月支出的大數字")
        XCTAssertGreaterThan(hero.frame.height, 50, "當月支出不是大數字")
        XCTAssertLessThan(hero.frame.minY, element(in: app, labelContaining: "當月家庭公帳總額").frame.minY, "當月支出不在公帳代墊款上面")

        let filter = app.buttons["statistics.scope"]
        XCTAssertTrue(filter.waitForExistence(timeout: 3), "toolbar 沒有視角的篩選按鈕")
        XCTAssertEqual(filter.label, "視角", "篩選按鈕的 VoiceOver 標籤不是「視角」")
        XCTAssertEqual(filter.value as? String, "全部", "篩選按鈕的 VoiceOver 值不是目前的視角")

        choose("個人私帳", from: filter, in: app)
        XCTAssertTrue(element(in: app, labelContaining: "當月家庭公帳總額").waitForNonExistence(timeout: 5), "私帳視角還看得到公帳代墊款")
        XCTAssertEqual(filter.value as? String, "個人私帳", "切換視角後篩選按鈕的 VoiceOver 值沒有跟著變")

        // 範例的預算額度：餐飲 100,已花 120。
        let dining = app.buttons["budgets.row.餐飲"]
        scrollAboveTabBar(dining, in: app)
        XCTAssertEqual(dining.label, "餐飲，預算 100 元，已花 120 元，超支 20 元", "餐飲沒有念出分類、預算、已花和超支")
    }

    /// 月份切換跟交易頁是同一個膠囊「‹ 2026年10月 ›」(#164):上一月、下一月、點中間選任意年月。
    @MainActor
    func testMonthPillSwitchesMonths() throws {
        let app = launchSignedIn()
        app.tabBars.buttons["統計"].tap()

        let title = app.buttons["statistics.month.title"]
        let previous = app.buttons["statistics.month.previous"]
        let next = app.buttons["statistics.month.next"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "統計頁沒有年月膠囊")
        let current = title.value as? String
        XCTAssertNotNil(current)
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44, "上一月的觸控範圍不到 44pt")
        XCTAssertGreaterThanOrEqual(next.frame.height, 44, "下一月的觸控範圍不到 44pt")

        previous.tap()
        XCTAssertNotEqual(title.value as? String, current, "上一月沒有換月份")
        next.tap()
        XCTAssertEqual(title.value as? String, current, "下一月沒有換回來")

        // 點年月選任意年月:2025 年 3 月。
        title.tap()
        let year = app.pickerWheels.element(boundBy: 0)
        let month = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(year.waitForExistence(timeout: 3), "沒有打開選年月")
        year.adjust(toPickerWheelValue: "2025年")
        month.adjust(toPickerWheelValue: "3月")
        app.buttons["statistics.month.done"].tap()
        XCTAssertEqual(title.value as? String, "2025年3月", "選了 2025年3月 但年月沒有跟著變")
    }

    /// 預算額度只列有預算或本月已花的分類(#76):範例是餐飲、交通、購物;點整列打開設定 sheet,不再有「設定／調整」按鈕。
    @MainActor
    func testAdjustBudgetByTappingRow() throws {
        let app = launchSignedIn()
        app.tabBars.buttons["統計"].tap()

        let transport = app.buttons["budgets.row.交通"]
        scrollAboveTabBar(transport, in: app)
        XCTAssertTrue(transport.isHittable, "預算額度沒有交通這一列")
        XCTAssertEqual(transport.label, "交通，預算未設定，已花 250 元", "沒有預算的列沒有念出「預算未設定」")
        XCTAssertFalse(app.buttons["budgets.row.娛樂"].exists, "沒有預算也沒有已花的娛樂也列出來了")

        transport.tap()
        let amount = app.textFields["budgetEditor.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "點整列沒有打開設定 sheet")
        XCTAssertEqual(amount.value as? String, "5000", "沒有預算時沒有預設 5000")
        app.buttons["budgetEditor.save"].tap()

        let updated = element(in: app, labelContaining: "交通，預算 5,000 元，已花 250 元")
        XCTAssertTrue(updated.waitForExistence(timeout: 5), "設定後沒有顯示預算")
    }

    /// section 底部的「新增預算額度」直接打開設定 sheet(#101):預設選第一個還沒列出的分類，其他分類在 sheet 的分類格裡選。
    @MainActor
    func testAddBudgetOpensEditorDirectly() throws {
        let app = launchSignedIn()
        app.tabBars.buttons["統計"].tap()

        let add = app.buttons["budgets.add"]
        scrollAboveTabBar(add, in: app)
        XCTAssertTrue(add.isHittable, "預算額度底部沒有「新增預算額度」")
        XCTAssertEqual(add.label, "新增預算額度")

        add.tap()
        // 直接打開編輯，不先跳選單;預設是第一個還沒列出的支出分類(範例資料已列出餐飲、交通、購物)。
        XCTAssertTrue(app.navigationBars["設定 汽機車輛 的預算"].waitForExistence(timeout: 3), "沒有直接打開預設分類的設定 sheet")
        XCTAssertEqual(app.textFields["budgetEditor.amount"].value as? String, "5000", "沒有預算時沒有預設 5000")

        // 在 sheet 的分類格裡改選娛樂。金額在格子上面，格子在下面:sheet 預設半高，要往上捲才看得到。
        let entertainment = app.buttons["娛樂"]
        for _ in 0..<6 where !(entertainment.exists && entertainment.isHittable) { app.swipeUp() }
        XCTAssertTrue(entertainment.exists && entertainment.isHittable, "分類格裡找不到娛樂")
        entertainment.tap()
        XCTAssertTrue(app.navigationBars["設定 娛樂 的預算"].waitForExistence(timeout: 3), "選了娛樂標題沒有跟著變")
        app.buttons["budgetEditor.save"].tap()

        let row = app.buttons["budgets.row.娛樂"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "設定後預算額度沒有多一列娛樂")
        XCTAssertEqual(row.label, "娛樂，預算 5,000 元，已花 0 元", "新的一列沒有念出分類、預算和已花")
    }

    /// 點 toolbar 的篩選按鈕打開選單，再點選項。
    @MainActor
    private func choose(_ option: String, from filter: XCUIElement, in app: XCUIApplication) {
        filter.tap()
        let item = app.buttons[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "視角選單裡沒有「\(option)」")
        item.tap()
    }

    /// 往上捲到元素完整露出在 tab bar 上方再點(tab bar 浮在清單上)。
    @MainActor
    private func scrollAboveTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<8 where !(element.exists && element.isHittable && element.frame.maxY < tabBar.frame.minY) {
            app.swipeUp()
        }
    }

    @MainActor
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication.launchUITesting(signedIn: true)
        return app
    }
}
