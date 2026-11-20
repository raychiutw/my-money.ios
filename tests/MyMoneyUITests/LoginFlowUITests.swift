import XCTest

/// 未登入 → tab 外殼 → 登出的端到端流程(#356:App 沒有自己的登入頁)。
///
/// 不連網路:app 以 `-uiTesting` 啟動，由 composition root 換成 in-memory repository,
/// 自動開的「登入視窗」不開系統視窗，直接以 MyMoneyTestSupport 的 `InMemoryAuthRepository.Member.sample` 登入(#334)。
/// `-uiTestingSignInResults` 指定每次登入的結果(cancel 是使用者關掉視窗、fail 是其他錯誤),才看得到未登入的畫面。
final class LoginFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 沒有 session 就自動登入，看到 5 個 tab(總覽、交易、帳戶、家庭、統計;規劃不再是 tab);「我的」顯示名稱與 email,設定有機器人記帳。
    /// 登出後停在登入入口頁(#367),不自動開登入視窗;按「登入」才開(這次讓它失敗，停在「重試」才看得到),按「重試」再登入。
    @MainActor
    func testSignInShowsTabShellAndSignOutShowsEntry() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingSignInResults", "ok,fail"], signedIn: true)
        XCTAssertFalse(app.staticTexts["我的記帳本"].exists, "不該有 App 自己的登入頁(#356)")

        XCTAssertEqual(
            app.tabBars.buttons.allElementsBoundByIndex.map(\.label), ["總覽", "記帳", "帳戶", "家庭", "統計"],
            "tab 的順序不是 總覽、交易、帳戶、家庭、統計"
        )
        XCTAssertFalse(app.tabBars.buttons["規劃"].exists, "規劃不該還是 tab")

        app.openMe()
        XCTAssertTrue(app.staticTexts["小明"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["family@example.com"].exists)
        XCTAssertFalse(app.buttons["me.household"].exists, "家庭已經升為 tab,「我的」不該還有它的入口")
        XCTAssertTrue(app.buttons["機器人記帳"].exists)

        XCTAssertFalse(app.buttons["週期收支"].exists, "規劃已搬到總覽的功能入口，「我的」不該還有")

        app.buttons["me.signOut"].tap()

        let entry = app.buttons["login.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "一般登入的人登出後沒有顯示登入入口頁")
        let retry = app.buttons["login.retry"]
        XCTAssertFalse(retry.exists, "登入入口頁不該自動開登入視窗")
        XCTAssertFalse(app.tabBars.buttons["總覽"].exists)

        entry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "入口頁按「登入」沒有開登入視窗")
        XCTAssertEqual(app.staticTexts["login.error"].label, "無法連線到伺服器")
        XCTAssertFalse(app.tabBars.buttons["總覽"].exists)

        retry.tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "按「重試」沒有再登入")
    }

    /// Face ID 登入的人登出(#364):停在登入入口頁(品牌與「登入」),不自動開登入視窗(這裡讓它失敗，開了就會看到「重試」);
    /// 按「登入」刷臉讀出保留的 session(假刷臉通過),進入 tab 外殼。
    @MainActor
    func testProtectedSignOutShowsEntryAndSignInUnlocks() throws {
        let app = XCUIApplication.launchUITesting(
            flags: ["-uiTestingProtectedSession", "-uiTestingSignInResults", "fail"], signedIn: true
        )

        app.openMe()
        app.buttons["me.signOut"].tap()

        let entry = app.buttons["login.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Face ID 登入的人登出後沒有顯示登入入口頁")
        XCTAssertTrue(app.staticTexts["我的記帳本"].exists)
        XCTAssertFalse(app.buttons["login.retry"].exists, "登入入口頁不該自動開登入視窗")

        entry.tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "按「登入」沒有刷臉進入")
    }

    /// 登出後冷啟動仍停在入口頁(#367,記號存在 Keychain);按「登入」開的登入視窗被關掉就回到入口頁、不再重開,再按一次才登入。
    @MainActor
    func testSignOutEntrySurvivesRelaunchAndClosingSignInReturnsToIt() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)
        app.openMe()
        app.buttons["me.signOut"].tap()
        XCTAssertTrue(app.buttons["login.entry"].waitForExistence(timeout: 5), "登出後沒有顯示登入入口頁")
        app.terminate()

        let relaunched = XCUIApplication.launchUITesting(flags: ["-uiTestingSignInResults", "cancel"], resettingSession: false)
        let entry = relaunched.buttons["login.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "登出後冷啟動沒有停在登入入口頁")
        XCTAssertFalse(relaunched.tabBars.buttons["總覽"].exists, "登出後冷啟動不該自動登入")

        entry.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "關掉登入視窗後沒有回到登入入口頁")
        XCTAssertFalse(relaunched.tabBars.buttons["總覽"].exists, "關掉登入視窗後不該再自動開")

        entry.tap()
        XCTAssertTrue(relaunched.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "再按「登入」沒有登入")
    }

    /// 使用者關掉登入視窗:不顯示錯誤，自動再開(這次成功)。
    @MainActor
    func testClosingSignInReopensIt() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingSignInResults", "cancel,cancel"])

        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "關掉登入視窗後沒有自動再開")
        XCTAssertFalse(app.buttons["login.retry"].exists)
    }

    /// 其他錯誤:停住、顯示說明與「重試」,不無限重開;回到前景也不自動開。
    @MainActor
    func testErrorStopsUntilRetry() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingSignInResults", "fail"])

        let retry = app.buttons["login.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "登入失敗沒有顯示「重試」")
        XCTAssertEqual(app.staticTexts["login.error"].label, "無法連線到伺服器")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["總覽"].exists, "回到前景不該自動再開")

        retry.tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "按「重試」沒有再登入")
    }

    /// 登入後重開 app,直接進入 tab 外殼(session 存在 Keychain)。
    @MainActor
    func testSignedInSessionSurvivesRelaunch() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)
        app.terminate()

        // 重開時讓登入失敗:沒讀回 session 的話會停在「重試」,不會偷偷重新登入。
        let relaunched = XCUIApplication.launchUITesting(flags: ["-uiTestingSignInResults", "fail"], resettingSession: false)

        XCTAssertTrue(relaunched.tabBars.buttons["總覽"].waitForExistence(timeout: 5))
        XCTAssertFalse(relaunched.buttons["login.retry"].exists)
    }
}
