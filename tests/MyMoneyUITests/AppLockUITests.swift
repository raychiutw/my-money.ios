import XCTest

/// App 鎖(#298):`-uiTestingAppLock` 讓範例帳號開著鎖;`-uiTestingAuthResult` 控制假驗證器的結果。
/// 冷啟動(重啟讀回 session)才鎖;剛輸入密碼登入不鎖。
final class AppLockUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let lockFlags = ["-uiTestingAppLock"]

    @MainActor
    func testFreshLoginDoesNotLock() throws {
        let app = XCUIApplication.launchUITesting(flags: lockFlags, signedIn: true)
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 10) || app.buttons["house"].firstMatch.exists, "登入後沒有進到 app")
        XCTAssertFalse(app.otherElements["appLock.screen"].exists, "剛登入不該被鎖")
    }

    /// 重啟(讀回 session)+ 驗證失敗:鎖畫面維持、有說明、有「解鎖」按鈕,內容看不到、也沒有登出。
    @MainActor
    func testColdStartStaysLockedWhenAuthenticationFails() throws {
        let first = XCUIApplication.launchUITesting(flags: lockFlags, signedIn: true)
        XCTAssertTrue(first.tabBars.buttons["總覽"].waitForExistence(timeout: 10))
        first.terminate()

        let app = XCUIApplication.launchUITesting(flags: lockFlags + ["-uiTestingAuthResult", "fail"], resettingSession: false)
        let unlock = app.buttons["appLock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10), "重啟後沒有看到鎖畫面")
        XCTAssertTrue(unlock.isHittable)
        XCTAssertTrue(app.staticTexts["appLock.error"].waitForExistence(timeout: 5), "驗證失敗沒有說明")
        XCTAssertFalse(app.tabBars.buttons["總覽"].isHittable, "鎖著時背後的內容還點得到")
        XCTAssertFalse(app.textFields["login.email"].exists, "驗證失敗不該登出")
    }

    /// 重啟 + 驗證成功:自動解鎖,進到 app。
    @MainActor
    func testColdStartUnlocksWhenAuthenticationSucceeds() throws {
        let first = XCUIApplication.launchUITesting(flags: lockFlags, signedIn: true)
        XCTAssertTrue(first.tabBars.buttons["總覽"].waitForExistence(timeout: 10))
        first.terminate()

        let app = XCUIApplication.launchUITesting(flags: lockFlags, resettingSession: false)
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 10), "驗證成功後沒有進到 app")
        XCTAssertFalse(app.buttons["appLock.unlock"].exists)
    }

    /// 最大字級:「解鎖」按鈕完整、點得到。
    @MainActor
    func testUnlockButtonFitsAtAccessibilitySize() throws {
        let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"
        let first = XCUIApplication.launchUITesting(flags: lockFlags, contentSize: ax5, signedIn: true)
        XCTAssertTrue(first.tabBars.buttons["總覽"].waitForExistence(timeout: 10))
        first.terminate()
        let app = XCUIApplication.launchUITesting(flags: lockFlags + ["-uiTestingAuthResult", "cancel"], contentSize: ax5, resettingSession: false)
        let unlock = app.buttons["appLock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        XCTAssertTrue(unlock.isHittable, "最大字級下解鎖按鈕點不到:\(unlock.frame)")
        XCTAssertGreaterThanOrEqual(unlock.frame.height, 44)
    }
}
