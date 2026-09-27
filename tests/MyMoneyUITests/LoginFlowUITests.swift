import XCTest

/// 登入 → tab 外殼 → 登出的端到端流程。
///
/// 不連網路:app 以 `-uiTesting` 啟動，由 composition root 換成 in-memory repository
/// (帳密是 MyMoneyTestSupport 的 `InMemoryAuthRepository.Member.sample`)。
/// session 仍存在模擬器的 Keychain(UI 測試專用的 service),`-resetSession` 會在啟動時清掉。
final class LoginFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 登入後看到 5 個 tab,規劃列出三個項目，帳號 sheet 顯示名稱與 email,登出回到登入頁。
    @MainActor
    func testSignInShowsTabShellAndSignOutReturnsToLogin() throws {
        let app = launch(resettingSession: true)
        XCTAssertTrue(app.staticTexts["我的記帳本"].exists)
        XCTAssertTrue(app.staticTexts["家庭財務，輕鬆掌握"].exists)

        signIn(app)

        for tab in ["總覽", "交易", "帳戶", "統計", "規劃"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "缺少「\(tab)」tab")
        }
        app.tabBars.buttons["規劃"].tap()
        for item in ["固定收支", "儲蓄目標", "現金流預測"] {
            XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 3), "規劃缺少「\(item)」")
        }

        app.tabBars.buttons["總覽"].tap()
        app.buttons["overview.account"].tap()
        XCTAssertTrue(app.staticTexts["小明"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["family@example.com"].exists)
        XCTAssertTrue(app.buttons["家庭"].exists)
        XCTAssertTrue(app.buttons["機器人記帳"].exists)

        app.buttons["account.signOut"].tap()

        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.buttons["總覽"].exists)
    }

    /// 登入後重開 app,直接進入 tab 外殼(session 存在 Keychain)。
    @MainActor
    func testSignedInSessionSurvivesRelaunch() throws {
        let app = launch(resettingSession: true)
        signIn(app)
        app.terminate()

        let relaunched = launch(resettingSession: false)

        XCTAssertTrue(relaunched.tabBars.buttons["總覽"].waitForExistence(timeout: 5))
        XCTAssertFalse(relaunched.buttons["login.submit"].exists)
    }

    /// 密碼預設隱藏，按眼睛可以切換成明碼。
    @MainActor
    func testPasswordCanBeRevealed() throws {
        let app = launch(resettingSession: true)
        let secureField = app.secureTextFields["login.password"]
        XCTAssertTrue(secureField.waitForExistence(timeout: 5))
        secureField.tap()
        secureField.typeText("secret123")

        app.buttons["login.togglePassword"].tap()

        XCTAssertEqual(app.textFields["login.password"].value as? String, "secret123")
    }

    @MainActor
    private func launch(resettingSession: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (resettingSession ? ["-resetSession"] : [])
        app.launch()
        return app
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
