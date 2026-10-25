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

    /// 第一次:登入頁勾「下次使用 Face ID 登入」、輸入帳密登入成功才綁定;登出後登入頁就有 Face ID 按鈕。
    @MainActor
    func testRememberOnLoginThenUseButtonAfterSignOut() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometricLogin"], signedIn: false)
        let remember = app.switches["login.rememberBiometric"]
        XCTAssertTrue(remember.waitForExistence(timeout: 8), "登入頁沒有「下次使用 Face ID 登入」")
        XCTAssertFalse(app.buttons["login.biometric"].exists, "還沒綁定不該有 Face ID 按鈕")
        remember.tap()
        typeCredentials(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8), "登入後沒有進入 app")
        XCTAssertFalse(app.alerts.firstMatch.exists, "登入後不該再跳出詢問框")
        app.openMe()
        app.buttons["me.signOut"].tap()
        XCTAssertTrue(app.buttons["login.biometric"].waitForExistence(timeout: 8), "登出後登入頁沒有 Face ID 按鈕")
        XCTAssertFalse(remember.exists, "已綁定就不再提供勾選")
    }

    /// 沒勾選:登入後沒有綁定,登出後登入頁沒有 Face ID 按鈕。
    @MainActor
    func testNotRememberedWithoutTick() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometricLogin"], signedIn: false)
        XCTAssertTrue(app.switches["login.rememberBiometric"].waitForExistence(timeout: 8))
        typeCredentials(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        app.openMe()
        app.buttons["me.signOut"].tap()
        XCTAssertTrue(app.switches["login.rememberBiometric"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["login.biometric"].exists)
    }

    /// 「我的」開關:開啟要重新輸入帳密,密碼對才綁定;關閉就清掉,登出後登入頁沒有按鈕。
    @MainActor
    func testMeToggleBindsWithPasswordAndUnbindsOnOff() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometricLogin"], signedIn: true)
        app.tabBars.buttons["總覽"].tap()
        app.openMe()
        let toggle = app.switches["me.biometricLogin"]
        XCTAssertTrue(ScrollSupport.revealFully(toggle, in: app), "「我的」沒有 Face ID 登入開關")
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        let password = app.secureTextFields["biometricBind.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5), "沒有跳出輸入帳密的表單")
        password.tap()
        password.typeText("secret123")
        app.buttons["biometricBind.submit"].tap()
        XCTAssertTrue(password.waitForNonExistence(timeout: 5), "綁定成功後表單沒有關閉")
        XCTAssertEqual(toggle.value as? String, "1", "綁定成功後開關沒有打開")

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0", "關閉後開關沒有關")
        app.buttons["me.signOut"].tap()
        XCTAssertTrue(app.switches["login.rememberBiometric"].waitForExistence(timeout: 8), "清掉後登入頁應提供勾選")
        XCTAssertFalse(app.buttons["login.biometric"].exists, "關閉後登入頁不該還有 Face ID 按鈕")
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

    /// 開啟時密碼輸入錯:顯示後端訊息、不綁定,開關維持關閉。
    @MainActor
    func testMeBindWithWrongPasswordShowsError() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometricLogin"], signedIn: true)
        app.tabBars.buttons["總覽"].tap()
        app.openMe()
        let toggle = app.switches["me.biometricLogin"]
        XCTAssertTrue(ScrollSupport.revealFully(toggle, in: app))
        toggle.tap()
        let password = app.secureTextFields["biometricBind.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        password.typeText("wrong-password")
        app.buttons["biometricBind.submit"].tap()
        XCTAssertTrue(app.staticTexts["biometricBind.error"].waitForExistence(timeout: 5), "密碼錯沒有顯示訊息")
        app.buttons["biometricBind.close"].tap()
        XCTAssertTrue(password.waitForNonExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "密碼錯不該綁定")
    }
}
