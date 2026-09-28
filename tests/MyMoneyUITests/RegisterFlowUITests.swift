import XCTest

/// 從登入頁進入註冊頁 → 註冊 → tab 外殼的端到端流程。
///
/// 不連網路:app 以 `-uiTesting` 啟動，註冊走 MyMoneyTestSupport 的 in-memory repository。
final class RegisterFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 註冊成功後直接進入 tab 外殼，帳號 sheet 顯示新帳號的名稱與 email。
    @MainActor
    func testRegisterEntersTabShellWithNewAccount() throws {
        let app = launchResettingSession()
        let registerLink = app.buttons["login.register"]
        XCTAssertTrue(registerLink.waitForExistence(timeout: 5), "登入頁沒有「立即註冊」")
        registerLink.tap()
        XCTAssertTrue(app.staticTexts["開始記錄你的財務生活"].waitForExistence(timeout: 3))

        type("小美", into: app.textFields["register.name"])
        type("mei@example.com", into: app.textFields["register.email"])
        type("secret123", into: app.secureTextFields["register.password"])
        type("secret123", into: app.secureTextFields["register.confirmation"])
        app.buttons["register.submit"].tap()

        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "註冊後沒有進入 tab 外殼")
        app.buttons["overview.account"].tap()
        XCTAssertTrue(app.staticTexts["小美"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["mei@example.com"].exists)
    }

    /// 兩次密碼不一致時留在註冊頁並顯示提示;「登入」回到登入頁。
    @MainActor
    func testMismatchedPasswordsShowErrorAndBackReturnsToLogin() throws {
        let app = launchResettingSession()
        let registerLink = app.buttons["login.register"]
        XCTAssertTrue(registerLink.waitForExistence(timeout: 5))
        registerLink.tap()

        type("小美", into: app.textFields["register.name"])
        type("mei@example.com", into: app.textFields["register.email"])
        type("secret123", into: app.secureTextFields["register.password"])
        type("secret124", into: app.secureTextFields["register.confirmation"])
        app.buttons["register.submit"].tap()

        XCTAssertTrue(app.staticTexts["兩次密碼不一致"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.buttons["總覽"].exists)

        app.buttons["register.backToLogin"].tap()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launchResettingSession() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        return app
    }

    @MainActor
    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 3), "找不到欄位 \(field)")
        field.tap()
        // 系統的高強度密碼建議會用 sheet 蓋掉鍵盤，這時 typeText 只送得進 1 個字元。
        XCTAssertTrue(
            XCUIApplication().keyboards.firstMatch.waitForExistence(timeout: 3),
            "點了 \(field) 之後沒有出現鍵盤(可能被系統的高強度密碼建議擋住)"
        )
        field.typeText(text)
    }
}
