import XCTest

/// 規劃 → 現金流預測。資料來自 MyMoneyTestSupport 的 `InMemoryForecastRepository.sampleForToday()`(不連網路)。
final class ForecastUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 透支風險與最低餘額;購買力試算的三種評估結果。
    @MainActor
    func testRiskAndPurchaseCheck() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.openPlanning()
        app.buttons["現金流預測"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "現金流充裕安全").waitForExistence(timeout: 5), "沒有看到透支風險")
        XCTAssertTrue(element(in: app, labelContaining: "最低餘額 53,440 元").exists, "沒有看到最低餘額")

        let amount = app.textFields["forecast.purchaseAmount"]
        for _ in 0..<5 where !amount.isHittable { app.swipeUp() }
        amount.tap()
        amount.typeText("60000")
        app.buttons["forecast.check"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "不建議購買").waitForExistence(timeout: 5), "沒有顯示評估結果")
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
