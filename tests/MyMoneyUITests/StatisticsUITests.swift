import XCTest

/// 「統計」tab。資料來自 MyMoneyTestSupport 的 `InMemoryStatisticsRepository.sampleForToday()`(不連網路)。
final class StatisticsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 公帳代墊款與分攤建議;從 toolbar 的篩選按鈕切到個人視角時不顯示，導覽列副標題跟著變(#63);超支標示;設定一個預算額度。
    @MainActor
    func testHouseholdSharesScopeAndBudget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["統計"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "當月家庭公帳總額 10,000 元").waitForExistence(timeout: 5), "沒有看到公帳代墊款")
        XCTAssertTrue(element(in: app, labelContaining: "小美 轉 1,000 元 給 小明").exists, "沒有分攤建議")

        let filter = app.buttons["statistics.scope"]
        XCTAssertTrue(filter.waitForExistence(timeout: 3), "toolbar 沒有視角的篩選按鈕")
        XCTAssertEqual(filter.label, "視角", "篩選按鈕的 VoiceOver 標籤不是「視角」")
        XCTAssertEqual(filter.value as? String, "全部", "篩選按鈕的 VoiceOver 值不是目前的視角")
        XCTAssertTrue(subtitle("全部", in: app).waitForExistence(timeout: 3), "導覽列副標題沒有顯示目前的視角")

        choose("個人", from: filter, in: app)
        XCTAssertTrue(element(in: app, labelContaining: "當月家庭公帳總額").waitForNonExistence(timeout: 5), "個人視角還看得到公帳代墊款")
        XCTAssertTrue(subtitle("個人", in: app).waitForExistence(timeout: 3), "切換視角後導覽列副標題沒有跟著變")
        XCTAssertEqual(filter.value as? String, "個人", "切換視角後篩選按鈕的 VoiceOver 值沒有跟著變")

        let dining = element(in: app, labelContaining: "超支")
        for _ in 0..<5 where !dining.exists { app.swipeUp() }
        XCTAssertTrue(dining.exists, "餐飲沒有標示超支")

        let transport = app.buttons["budgets.edit.交通"]
        for _ in 0..<5 where !transport.isHittable { app.swipeUp() }
        transport.tap()
        let amount = app.textFields["budgetEditor.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        XCTAssertEqual(amount.value as? String, "5000", "沒有預算時沒有預設 5000")
        app.buttons["budgetEditor.save"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "已花 $250 / 預算 $5,000").waitForExistence(timeout: 5), "設定後沒有顯示預算")
    }

    /// 點 toolbar 的篩選按鈕打開選單，再點選項。
    @MainActor
    private func choose(_ option: String, from filter: XCUIElement, in app: XCUIApplication) {
        filter.tap()
        let item = app.buttons[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "視角選單裡沒有「\(option)」")
        item.tap()
    }

    /// 導覽列副標題(`navigationSubtitle`)。
    @MainActor
    private func subtitle(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts[text]
    }

    @MainActor
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "登入後沒有進入 tab 外殼")
    }
}
