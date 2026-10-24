import XCTest

/// 用 Face ID 登入(#308):登入成功後問一次要不要記住;之後登入頁用 Face ID 登入。
final class BiometricLoginUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func typeCredentials(_ app: XCUIApplication) {
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 8), "沒有登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        app.buttons["login.submit"].tap()
    }

    /// 第一次登入:先問要不要用 Face ID 登入;回答「開啟」才進入 app。
    @MainActor
    func testFirstLoginOffersBiometricLoginThenSignsIn() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometricLogin"], signedIn: false)
        typeCredentials(app)
        let offer = app.alerts["要用 Face ID 登入嗎？"]
        XCTAssertTrue(offer.waitForExistence(timeout: 8), "沒有詢問要不要用 Face ID 登入")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "回答前不該已經進入 app")
        offer.buttons["開啟"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "回答後沒有進入 app")
    }

    /// 回答「暫時不要」也會進入,而且沒有 Face ID 按鈕。
    @MainActor
    func testDecliningStillSignsIn() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometricLogin"], signedIn: false)
        typeCredentials(app)
        let offer = app.alerts["要用 Face ID 登入嗎？"]
        XCTAssertTrue(offer.waitForExistence(timeout: 8))
        offer.buttons["暫時不要"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
    }

    /// 已存帳密:登入頁有「使用 Face ID 登入」,按了驗證通過就直接進入,不用輸入。
    @MainActor
    func testSavedLoginSignsInWithOneTap() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingSavedLogin"], signedIn: false)
        let button = app.buttons["login.biometric"]
        XCTAssertTrue(button.waitForExistence(timeout: 8), "登入頁沒有 Face ID 按鈕")
        button.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "Face ID 登入後沒有進入 app")
    }

    /// 驗證被取消:留在登入頁,沒有錯誤訊息。
    @MainActor
    func testCancelledStaysOnLoginWithoutError() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingSavedLogin", "-uiTestingAuthResult", "cancel"], signedIn: false)
        let button = app.buttons["login.biometric"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()
        XCTAssertFalse(app.tabBars.firstMatch.waitForExistence(timeout: 2), "取消驗證不該進入 app")
        XCTAssertFalse(app.staticTexts["login.error"].exists)
        XCTAssertTrue(button.exists)
    }

    /// 沒存帳密、也沒有 Face ID:登入頁沒有那顆按鈕。
    @MainActor
    func testNoButtonWithoutSavedLogin() throws {
        let app = XCUIApplication.launchUITesting(signedIn: false)
        XCTAssertTrue(app.textFields["login.email"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["login.biometric"].exists)
    }
}
