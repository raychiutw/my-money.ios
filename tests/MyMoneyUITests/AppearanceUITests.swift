import XCTest

/// 「我的」的外觀設定(跟隨系統、淺色、深色):三列打勾，點一下就生效(ADR-0004)。
///
/// 選擇只記在這台裝置(UI 測試專用的 UserDefaults);`-resetSession` 會清空它，所以每個 UI 測試從「跟隨系統」開始。
/// 畫面實際的深淺不寫自動測試，用截圖驗證(#60 的 Testing Decisions)。
final class AppearanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 預設是跟隨系統;點一下「深色」就選起來，重開 app(不帶 `-resetSession`)仍是深色，再切回跟隨系統。
    @MainActor
    func testAppearanceChoiceSurvivesRelaunch() throws {
        let app = launch(resettingSession: true)
        app.signInWithSampleAccount()
        openAppearance(in: app)
        XCTAssertEqual(selectedOption(in: app), "跟隨系統", "外觀的預設值不是跟隨系統")
        for option in ["跟隨系統", "淺色", "深色"] {
            XCTAssertTrue(app.buttons[option].exists, "外觀缺少「\(option)」這一列")
        }

        app.buttons["深色"].tap()
        XCTAssertEqual(selectedOption(in: app), "深色", "點一下深色，打勾沒有跟著變")
        app.terminate()

        let relaunched = launch(resettingSession: false)
        XCTAssertTrue(relaunched.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "重開 app 沒有直接進入 tab 外殼")
        openAppearance(in: relaunched)
        XCTAssertEqual(selectedOption(in: relaunched), "深色", "重開 app 之後外觀沒有沿用深色")

        relaunched.buttons["跟隨系統"].tap()
        XCTAssertEqual(selectedOption(in: relaunched), "跟隨系統", "沒辦法切回跟隨系統")
    }

    /// 打開「我的」,等外觀的三列出現。
    @MainActor
    private func openAppearance(in app: XCUIApplication) {
        app.openMe()
        XCTAssertTrue(app.buttons["跟隨系統"].waitForExistence(timeout: 3), "「我的」沒有「外觀」的選項")
    }

    /// 目前打勾的那一列(被選中的那一列 `isSelected`)。
    @MainActor
    private func selectedOption(in app: XCUIApplication) -> String {
        let selected = ["跟隨系統", "淺色", "深色"].filter { app.buttons[$0].isSelected }
        XCTAssertEqual(selected.count, 1, "應該剛好一列打勾，實際是 \(selected)")
        return selected.first ?? ""
    }

    @MainActor
    private func launch(resettingSession: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (resettingSession ? ["-resetSession"] : [])
        app.launch()
        return app
    }

}
