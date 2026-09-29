import XCTest

/// 帳戶 tab 的結帳日出帳作業、校準未出帳與信用卡扣款還款。資料來自 MyMoneyTestSupport 的 `SampleAccounts`(不連網路)。
final class CardSettlementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 有未出帳款就能做出帳作業(先確認),完成後顯示後端的訊息;按鈕的 VoiceOver 念出卡名。
    /// 信用卡扣款還款：從卡片上的「繳家庭代墊」打開(帶入 3,000),已出帳待繳款從 12,000 變成 9,000。
    @MainActor
    func testRolloverAndPayment() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()

        let rollover = app.buttons["accounts.rollover.sample-low-limit-card"]
        for _ in 0..<5 where !rollover.isHittable { app.swipeUp() }
        XCTAssertEqual(rollover.label, "「iOS 測試小額卡」出帳作業", "出帳作業的按鈕沒有念出卡名")
        rollover.tap()
        XCTAssertTrue(
            element(in: app, labelContaining: "確定要將「iOS 測試小額卡」的未出帳款 $5,000 轉入本期已出帳待繳款嗎？")
                .waitForExistence(timeout: 3),
            "沒有先確認就做出帳作業"
        )
        app.buttons["出帳作業"].firstMatch.tap()
        // 後端的原文(疊字已回報 onion523/my-money#27),照原樣顯示。
        XCTAssertTrue(
            element(in: app, labelContaining: "已將未出帳 NT$ 5,000 成功出帳作業為已出帳待繳款！").waitForExistence(timeout: 5),
            "沒有顯示出帳作業的結果"
        )
        app.buttons["好"].tap()

        let payShared = app.buttons["accounts.payShared.sample-card"]
        for _ in 0..<5 where !payShared.isHittable { app.swipeUp() }
        payShared.tap()
        let amount = app.textFields["cardPayment.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開信用卡扣款還款")
        XCTAssertEqual(amount.value as? String, "3000", "「繳家庭代墊」沒有帶入家庭公帳的欠款")
        // 歸屬是表單裡一般的選擇列，表單裡沒有分段控制(#65)。選單樣式的 `Picker` 沒有 accessibility value,
        // 值是選擇列裡唯一的文字。
        let ownership = app.buttons["cardPayment.ownership"]
        XCTAssertTrue(ownership.exists, "信用卡扣款還款的歸屬不是表單選擇列")
        XCTAssertEqual(ownership.staticTexts.firstMatch.label, "家庭公帳", "「繳家庭代墊」的歸屬不是家庭公帳")
        let form = app.collectionViews.containing(.textField, identifier: "cardPayment.amount").firstMatch
        XCTAssertEqual(form.segmentedControls.count, 0, "信用卡扣款還款的表單裡還有分段控制")
        // 點金額欄全選後重打一次，直接取代原值(#32)。
        amount.tap()
        amount.typeText("3000")
        XCTAssertEqual(amount.value as? String, "3000")
        app.buttons["cardPayment.submit"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "已出帳待繳款、$9,000").waitForExistence(timeout: 5), "還款後已出帳待繳款沒有更新")
    }

    /// 校準未出帳(#48):先確認(說明重算的期間、會扣掉刷退和還款，以及未出帳款可能被算少),完成後顯示後端的訊息。
    @MainActor
    func testReconcileUnbilled() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()

        let reconcile = app.buttons["accounts.reconcile.sample-card"]
        for _ in 0..<5 where !(reconcile.exists && reconcile.isHittable) { app.swipeUp() }
        reconcile.tap()
        XCTAssertTrue(
            element(in: app, labelContaining: "這段期間繳過已出帳待繳款的話，未出帳款會被算少。").waitForExistence(timeout: 3),
            "確認時沒有提醒未出帳款會被算少"
        )
        app.buttons["校準"].firstMatch.tap()

        XCTAssertTrue(
            element(in: app, labelContaining: "已自動校準「iOS 測試信用卡」未出帳金額為 NT$ 3,500").waitForExistence(timeout: 5),
            "沒有顯示校準的結果"
        )
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
