import XCTest

/// 「我的」:姓名與 email、分頁「設定｜規劃」、版本(ADR-0004、#84)。
///
/// 外觀的三列打勾在 `AppearanceUITests`,規劃底下三個畫面各自的功能在 `RecurringUITests`、
/// `SavingsGoalsUITests`、`ForecastUITests`(它們都從「我的」的規劃進去)。
final class MeSheetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 規劃不再是 tab;打開「我的」先顯示設定，切到規劃看得到三個項目，關掉再打開又回到設定(不記憶分頁)。
    @MainActor
    func testOpensOnSettingsAndPlanningIsOneSwitchAway() throws {
        let app = launchAndSignIn()
        XCTAssertFalse(app.tabBars.buttons["規劃"].exists, "規劃不該還是 tab")

        app.openMe()
        XCTAssertTrue(app.buttons["me.signOut"].waitForExistence(timeout: 5), "「我的」沒有先顯示設定")
        XCTAssertTrue(app.buttons["me.bot"].exists, "設定沒有機器人記帳")
        XCTAssertFalse(app.buttons["me.household"].exists, "家庭已經升為 tab,設定不該還有它的入口")
        XCTAssertFalse(app.buttons["週期收支"].exists, "設定分頁不該看到規劃的項目")

        app.segmentedControls["me.page"].buttons["規劃"].tap()
        for item in ["週期收支", "儲蓄目標", "現金流預測"] {
            XCTAssertTrue(app.buttons[item].waitForExistence(timeout: 3), "規劃缺少「\(item)」")
        }
        XCTAssertFalse(app.buttons["me.signOut"].exists, "規劃分頁不該看到登出")

        app.buttons["me.close"].tap()
        XCTAssertTrue(app.buttons["週期收支"].waitForNonExistence(timeout: 5), "「我的」沒有關閉")

        app.openMe()
        XCTAssertTrue(app.buttons["me.signOut"].waitForExistence(timeout: 5), "重新打開之後沒有回到設定(分頁不該被記住)")
        XCTAssertFalse(app.buttons["週期收支"].exists, "重新打開之後還停在規劃")
    }

    /// 設定底部顯示「版本 版號（build）」。
    @MainActor
    func testSettingsShowsTheVersion() throws {
        let app = launchAndSignIn()

        app.openMe()
        XCTAssertTrue(app.buttons["me.signOut"].waitForExistence(timeout: 5))
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "版本 ")).firstMatch
        XCTAssertTrue(version.exists, "設定底部沒有版本文字")
        XCTAssertTrue(version.label.contains("（") && version.label.hasSuffix("）"), "版本文字沒有 build 號:\(version.label)")
    }

    @MainActor
    private func launchAndSignIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "登入後沒有進入 tab 外殼")
        return app
    }
}
