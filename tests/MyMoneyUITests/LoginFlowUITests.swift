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

    /// 登入後看到 4 個 tab(規劃不再是 tab);「我的」顯示名稱與 email,設定有機器人記帳,規劃列出三個項目，登出回到登入頁。
    @MainActor
    func testSignInShowsTabShellAndSignOutReturnsToLogin() throws {
        let app = launch(resettingSession: true)
        XCTAssertTrue(app.staticTexts["我的記帳本"].exists)
        XCTAssertTrue(app.staticTexts["家庭財務，輕鬆掌握"].exists)
        XCTAssertTrue(app.staticTexts["登入帳號"].exists)

        signIn(app)

        for tab in ["總覽", "交易", "帳戶", "統計"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "缺少「\(tab)」tab")
        }
        XCTAssertFalse(app.tabBars.buttons["規劃"].exists, "規劃不該還是 tab")

        app.openMe()
        XCTAssertTrue(app.staticTexts["小明"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["family@example.com"].exists)
        // 用 identifier 找「家庭群組」。以前找的是「家庭」,其實是被「我的」蓋住的總覽視角分段控制，
        // 視角改進 toolbar 選單(#63)之後就找不到了。家庭升為 tab 之後(#85)這個入口會移除。
        XCTAssertTrue(app.buttons["me.household"].exists, "「我的」沒有「家庭群組」")
        XCTAssertTrue(app.buttons["機器人記帳"].exists)

        app.segmentedControls["me.page"].buttons["規劃"].tap()
        for item in ["週期收支", "儲蓄目標", "現金流預測"] {
            XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 3), "規劃缺少「\(item)」")
        }
        app.segmentedControls["me.page"].buttons["設定"].tap()

        app.buttons["me.signOut"].tap()

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
