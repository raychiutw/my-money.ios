import XCTest

/// 帳號 sheet → 機器人記帳。資料來自 MyMoneyTestSupport 的 `InMemoryBotRepository.sample()`(不連網路)。
final class BotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 產生綁定驗證碼並複製指令;webhook 網址正確;模擬對話用快捷範例送出後出現回覆。
    @MainActor
    func testPairingAndSimulatedChat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.buttons["overview.account"].tap()
        app.buttons["機器人記帳"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "小明的 LINE").waitForExistence(timeout: 5), "沒有看到已綁定的帳號")

        app.buttons["bot.generate"].tap()
        XCTAssertTrue(app.staticTexts["bot.pairingCode"].waitForExistence(timeout: 3), "沒有顯示綁定驗證碼")
        XCTAssertTrue(element(in: app, labelContaining: "綁定 AB12CD").exists, "沒有顯示要傳送的指令")
        app.buttons["bot.copyCommand"].tap()
        XCTAssertTrue(app.buttons["已複製指令"].waitForExistence(timeout: 2), "複製後沒有顯示「已複製指令」")

        let webhook = app.staticTexts["https://my-money-api.onion523.workers.dev/bot/webhook/line"]
        for _ in 0..<5 where !webhook.exists { app.swipeUp() }
        XCTAssertTrue(webhook.exists, "webhook 網址不對")

        app.buttons["模擬對話"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "會寫入真的交易紀錄").waitForExistence(timeout: 3), "沒有告知會寫入真的交易")
        app.buttons["午餐 120"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "記帳成功：午餐 120").waitForExistence(timeout: 5), "送出後沒有回覆")
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
