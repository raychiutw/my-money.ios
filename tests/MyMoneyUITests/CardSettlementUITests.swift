import XCTest

/// 帳戶 tab 的結帳日出帳結轉與信用卡還款沖銷。資料來自 MyMoneyTestSupport 的 `SampleAccounts`(不連網路)。
final class CardSettlementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 小額卡的結帳日是 1 號，任何一天都已經過了：一鍵出帳(先確認)後顯示後端的訊息。
    /// 信用卡還款沖銷：繳家庭代墊 3,000,已出帳待繳金額從 12,000 變成 9,000。
    @MainActor
    func testRolloverAndPayment() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()

        let rollover = app.buttons["accounts.rollover.sample-low-limit-card"]
        for _ in 0..<5 where !rollover.isHittable { app.swipeUp() }
        rollover.tap()
        XCTAssertTrue(element(in: app, labelContaining: "結轉為本期已出帳待繳嗎？").waitForExistence(timeout: 3), "沒有先確認就結轉")
        app.buttons["結轉"].firstMatch.tap()
        XCTAssertTrue(element(in: app, labelContaining: "成功結轉為已出帳待繳").waitForExistence(timeout: 5), "沒有顯示結轉的結果")
        app.buttons["好"].tap()

        let pay = app.buttons["accounts.pay.sample-card"]
        for _ in 0..<5 where !pay.isHittable { app.swipeUp() }
        pay.tap()
        let fillShared = app.buttons["cardPayment.fillShared"]
        XCTAssertTrue(fillShared.waitForExistence(timeout: 3), "沒有「繳家庭代墊」")
        // 先點金額欄(全選預填的待繳總額),再填入比較短的 3000:選取範圍還是舊字串的，不能因此出錯(#32)。
        app.textFields["cardPayment.amount"].tap()
        fillShared.tap()
        XCTAssertEqual(app.textFields["cardPayment.amount"].value as? String, "3000")
        app.buttons["cardPayment.submit"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "已出帳待繳金額、$9,000").waitForExistence(timeout: 5), "還款後已出帳待繳金額沒有更新")
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
