import XCTest

/// 「統計」tab。資料來自 MyMoneyTestSupport 的 `InMemoryStatisticsRepository.sampleForToday()`(不連網路)。
final class StatisticsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 公帳代墊款與分攤建議;個人視角時不顯示;超支標示;設定一個分類預算。
    @MainActor
    func testHouseholdSharesScopeAndBudget() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["統計"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "當月家庭公帳總額 10,000 元").waitForExistence(timeout: 5), "沒有看到公帳代墊款")
        XCTAssertTrue(element(in: app, labelContaining: "小美 轉 1,000 元 給 小明").exists, "沒有分攤建議")

        app.buttons["個人"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "當月家庭公帳總額").waitForNonExistence(timeout: 5), "個人視角還看得到公帳代墊款")

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
