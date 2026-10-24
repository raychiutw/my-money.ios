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

/// 設定開關(#299):在「我的」裡開啟與關閉,都要先驗證成功。
extension AppLockUITests {
    @MainActor
    func testSettingsToggleEnablesLockAfterAuthentication() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometry"], signedIn: true)
        declineOfferIfShown(in: app)
        app.openMe()
        let toggle = app.switches["me.appLock"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "「我的」沒有 App 鎖開關")
        XCTAssertEqual(toggle.value as? String, "0", "預設應該是關的")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let on = NSPredicate(format: "value == %@", "1")
        expectation(for: on, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testSettingsToggleStaysOffWhenAuthenticationIsCancelled() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometry", "-uiTestingAuthResult", "cancel"], signedIn: true)
        declineOfferIfShown(in: app)
        app.openMe()
        let toggle = app.switches["me.appLock"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(toggle.value as? String, "0", "取消驗證後開關不該打開")
    }
}

/// 登入後主動詢問(#300):第一次登入問一次,選「暫時不要」之後登出再登入不再問。
extension AppLockUITests {
    func declineOfferIfShown(in app: XCUIApplication) {
        let decline = app.alerts.buttons["暫時不要"]
        if decline.waitForExistence(timeout: 5) { decline.tap() }
    }

    @MainActor
    func testOfferIsShownOnFirstLoginAndOnlyOnce() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometry"], signedIn: true)
        let decline = app.alerts.buttons["暫時不要"]
        XCTAssertTrue(decline.waitForExistence(timeout: 8), "第一次登入沒有詢問要不要開啟 Face ID")
        decline.tap()
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2))

        // 登出再登入:不再問。
        app.openMe()
        app.buttons["me.signOut"].tap()
        app.signInWithSampleAccount()
        XCTAssertFalse(app.alerts.buttons["暫時不要"].waitForExistence(timeout: 3), "登出再登入不該再問")
    }

    @MainActor
    func testAcceptingOfferEnablesLock() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingBiometry"], signedIn: true)
        let accept = app.alerts.buttons["開啟"]
        XCTAssertTrue(accept.waitForExistence(timeout: 8))
        accept.tap()
        app.openMe()
        let toggle = app.switches["me.appLock"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let on = NSPredicate(format: "value == %@", "1")
        expectation(for: on, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
    }
}

/// 鎖要蓋得住 sheet(code review):開著「我的」離開超過寬限時間再回來,sheet 裡的內容不能還點得到。
extension AppLockUITests {
    @MainActor
    func testLockCoversAnOpenSheetAfterTheGracePeriod() throws {
        let app = XCUIApplication.launchUITesting(
            flags: ["-uiTestingAppLock", "-uiTestingAuthResult", "fail", "-uiTestingLockGrace", "2"], signedIn: true
        )
        app.openMe()
        let signOut = app.buttons["me.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5), "「我的」沒有打開")

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 4)
        app.activate()

        let unlock = app.buttons["appLock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10), "離開超過寬限時間回來沒有鎖畫面")
        XCTAssertFalse(signOut.isHittable, "鎖著時「我的」sheet 裡的內容還點得到")
    }
}
