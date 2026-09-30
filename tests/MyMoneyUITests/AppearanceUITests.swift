import XCTest

/// 帳號 sheet 的外觀設定(跟隨系統、淺色、深色)。
///
/// 選擇只記在這台裝置(UI 測試專用的 UserDefaults);`-resetSession` 會清空它，所以每個 UI 測試從「跟隨系統」開始。
/// 畫面實際的深淺不寫自動測試，用截圖驗證(#60 的 Testing Decisions)。
final class AppearanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 預設是跟隨系統;選「深色」之後重開 app(不帶 `-resetSession`)仍是深色，再切回跟隨系統。
    @MainActor
    func testAppearanceChoiceSurvivesRelaunch() throws {
        let app = launch(resettingSession: true)
        signIn(app)
        let appearance = openAppearance(in: app)
        XCTAssertEqual(selection(of: appearance), "跟隨系統", "外觀的預設值不是跟隨系統")

        choose("深色", for: appearance, in: app)
        XCTAssertEqual(selection(of: appearance), "深色", "選了深色，選擇列沒有跟著變")
        app.terminate()

        let relaunched = launch(resettingSession: false)
        XCTAssertTrue(relaunched.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "重開 app 沒有直接進入 tab 外殼")
        let relaunchedAppearance = openAppearance(in: relaunched)
        XCTAssertEqual(selection(of: relaunchedAppearance), "深色", "重開 app 之後外觀沒有沿用深色")

        choose("跟隨系統", for: relaunchedAppearance, in: relaunched)
        XCTAssertEqual(selection(of: relaunchedAppearance), "跟隨系統", "沒辦法切回跟隨系統")
    }

    /// 打開帳號 sheet,回傳「外觀」選擇列。
    @MainActor
    private func openAppearance(in app: XCUIApplication) -> XCUIElement {
        app.buttons["toolbar.me"].tap()
        let appearance = app.buttons["account.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 3), "帳號 sheet 沒有「外觀」選擇列")
        return appearance
    }

    /// 選擇列右邊顯示的值。選單樣式的 `Picker` 沒有 accessibility value,值是選擇列裡唯一的文字。
    @MainActor
    private func selection(of picker: XCUIElement) -> String {
        picker.staticTexts.firstMatch.label
    }

    /// 點選擇列打開選單，再點選項。
    @MainActor
    private func choose(_ option: String, for picker: XCUIElement, in app: XCUIApplication) {
        picker.tap()
        let item = app.buttons[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "外觀選單裡沒有「\(option)」")
        item.tap()
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
