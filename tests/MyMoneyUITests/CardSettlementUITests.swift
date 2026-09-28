import XCTest

/// 帳戶 tab 的結帳日出帳結轉與信用卡還款沖銷。資料來自 MyMoneyTestSupport 的 `SampleAccounts`(不連網路)。
final class CardSettlementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 有未出帳金額就能出帳結轉(先確認)，結轉後顯示後端的訊息。
    /// 信用卡還款沖銷：從卡片上的「繳家庭代墊」打開(帶入 3,000),已出帳待繳金額從 12,000 變成 9,000。
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

        let payShared = app.buttons["accounts.payShared.sample-card"]
        for _ in 0..<5 where !payShared.isHittable { app.swipeUp() }
        payShared.tap()
        let amount = app.textFields["cardPayment.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開信用卡還款沖銷")
        XCTAssertEqual(amount.value as? String, "3000", "「繳家庭代墊」沒有帶入家庭公帳的欠款")
        // 點金額欄全選後重打一次，直接取代原值(#32)。
        amount.tap()
        amount.typeText("3000")
        XCTAssertEqual(amount.value as? String, "3000")
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
