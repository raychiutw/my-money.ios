import XCTest

/// 「帳戶」tab 的瀏覽畫面。資料來自 MyMoneyTestSupport 的 `SampleAccounts`(不連網路)。
///
/// 每一列都合併成一個 accessibility element(VoiceOver 一次念完),所以用 label 的內容找元素。
final class AccountsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 顯示三張統計卡、銀行存款帳戶與信用卡帳戶兩區，以及剩餘額度不足的警示。
    @MainActor
    func testAccountsTabShowsSummaryAndBothSections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["帳戶"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "iOS 測試存款,餘額 50,000 元").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, labelContaining: "銀行存款帳戶餘額合計 50,000 元").exists)
        XCTAssertTrue(element(in: app, labelContaining: "待繳卡費總額 28,500 元").exists)
        XCTAssertTrue(element(in: app, labelContaining: "淨可用資產 21,500 元").exists)
        XCTAssertTrue(element(in: app, labelContaining: "iOS 測試信用卡").exists)
        XCTAssertTrue(element(in: app, labelContaining: "額度不足").exists, "小額卡沒有顯示剩餘額度不足的警示")
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
