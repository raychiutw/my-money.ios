import XCTest

/// 每個 tab 主頁面右上角的頭像按鈕(ADR-0004、#83)。
///
/// 範例帳號的姓名是「小明」(MyMoneyTestSupport 的 `InMemoryAuthRepository.Member.sample`)。
final class MeButtonUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 依序切到每個 tab:主頁面右上角都有頭像按鈕，點了打開同一個帳號 sheet，關閉後回到原本的 tab。
    @MainActor
    func testEveryTabRootOpensAndClosesTheSameSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        for tab in ["總覽", "交易", "帳戶", "統計", "規劃"] {
            app.tabBars.buttons[tab].tap()
            let me = app.buttons["toolbar.me"]
            XCTAssertTrue(me.waitForExistence(timeout: 5), "「\(tab)」主頁面右上角沒有頭像按鈕")

            me.tap()
            XCTAssertTrue(app.buttons["account.signOut"].waitForExistence(timeout: 5), "在「\(tab)」點頭像沒有打開帳號 sheet")

            app.buttons["account.close"].tap()
            XCTAssertTrue(app.buttons["account.signOut"].waitForNonExistence(timeout: 5), "在「\(tab)」關閉之後帳號 sheet 還在")
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, "關閉帳號 sheet 之後沒有回到「\(tab)」")
        }
    }

    /// VoiceOver 念「我的，姓名」。頭像上的字是姓名的第一個字，這個規則由 `AvatarInitialTests` 驗證
    /// (工具列按鈕會把裡面的字併進按鈕的 label,UI 測試查不到單獨的文字)。
    @MainActor
    func testAvatarIsLabelledForVoiceOver() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let me = app.buttons["toolbar.me"]
        XCTAssertTrue(me.waitForExistence(timeout: 5), "總覽沒有頭像按鈕")
        XCTAssertEqual(me.label, "我的，小明", "頭像按鈕的 VoiceOver 標籤不對")
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
