import XCTest

/// 「總覽」tab。資料來自 MyMoneyTestSupport 的範例資料(日期相對於今天，不連網路)。
final class OverviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 從總覽記一筆 250 元 → 當月淨收支和最近交易跟著更新;「查看全部」進入交易 tab。
    @MainActor
    func testQuickEntryUpdatesMonthNetAndRecent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        // 範例：收入 45,000,支出 120 + 880(信用卡還款不算)。
        XCTAssertTrue(element(in: app, labelContaining: "當月淨收支 44,000 元").waitForExistence(timeout: 5), "沒有看到當月淨收支")
        XCTAssertTrue(element(in: app, labelContaining: "有 1 個分類支出已超出預算").exists, "沒有超支警示")

        app.buttons["overview.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("250")
        app.buttons["quickEntry.save"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "當月淨收支 43,750 元").waitForExistence(timeout: 5), "記一筆後當月淨收支沒有更新")
        XCTAssertTrue(element(in: app, labelContaining: "支出 250 元").exists, "記一筆後最近交易沒有更新")

        let showAll = app.buttons["查看全部"]
        for _ in 0..<5 where !showAll.isHittable { app.swipeUp() }
        showAll.tap()
        XCTAssertTrue(app.buttons["transactions.add"].waitForExistence(timeout: 3), "「查看全部」沒有進入交易 tab")
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
