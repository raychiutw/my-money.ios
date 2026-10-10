import XCTest

/// 「我的」:姓名與 email、設定、版本(ADR-0004、#84、#178)。
///
/// 外觀的三列打勾在 `AppearanceUITests`,規劃的三個畫面各自的功能在 `RecurringUITests`、
/// `SavingsGoalsUITests`、`ForecastUITests`(它們都從總覽的功能入口進去)。
final class MeSheetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 「我的」只剩設定:機器人記帳、外觀、登出、版本,沒有「設定｜規劃」分頁選擇器;週期收支、儲蓄目標、現金流預測在總覽的功能入口(#178)。
    @MainActor
    func testMeHasOnlySettingsAndNoPlanningPage() throws {
        let app = launchAndSignIn()
        XCTAssertFalse(app.tabBars.buttons["規劃"].exists, "規劃不該還是 tab")

        app.openMe()
        XCTAssertTrue(app.buttons["me.signOut"].waitForExistence(timeout: 5), "「我的」沒有顯示設定")
        XCTAssertTrue(app.buttons["me.bot"].exists, "設定沒有機器人記帳")
        XCTAssertFalse(app.buttons["me.household"].exists, "家庭已經升為 tab,設定不該還有它的入口")
        XCTAssertFalse(app.segmentedControls["me.page"].exists || app.buttons["me.page"].exists, "「我的」不該還有分頁選擇器")
        for item in ["週期收支", "儲蓄目標", "現金流預測"] {
            XCTAssertFalse(app.buttons[item].exists, "「我的」不該還有規劃的項目「\(item)」")
        }

        app.buttons["me.close"].tap()
        XCTAssertTrue(app.buttons["me.signOut"].waitForNonExistence(timeout: 5), "「我的」沒有關閉")
        for id in ["recurring", "goals", "forecast"] {
            XCTAssertTrue(
                ScrollSupport.revealFully(app.buttons["home.entry.\(id)"], in: app), "總覽的功能入口缺少「\(id)」(規劃搬到這裡)"
            )
        }
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
        let app = XCUIApplication.launchUITesting(signedIn: true)
        return app
    }
}
