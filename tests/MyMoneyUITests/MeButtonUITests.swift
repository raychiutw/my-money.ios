import XCTest

/// 每個 tab 主頁面右上角的頭像按鈕(ADR-0004、#83)。規劃在 #84 移出 tab,家庭在 #85 升為 tab。
///
/// 範例帳號的姓名是「小明」(MyMoneyTestSupport 的 `InMemoryAuthRepository.Member.sample`)。
final class MeButtonUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 依序切到每個 tab:主頁面右上角都有頭像按鈕，點了打開同一個「我的」，關閉後回到原本的 tab。
    @MainActor
    func testEveryTabRootOpensAndClosesTheSameSheet() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)

        for tab in ["總覽", "記帳", "帳戶", "家庭", "統計"] {
            app.tabBars.buttons[tab].tap()
            let me = app.buttons["toolbar.me"]
            XCTAssertTrue(me.waitForExistence(timeout: 5), "「\(tab)」主頁面右上角沒有頭像按鈕")

            me.tap()
            XCTAssertTrue(app.buttons["me.signOut"].waitForExistence(timeout: 5), "在「\(tab)」點頭像沒有打開「我的」")

            app.buttons["me.close"].tap()
            XCTAssertTrue(app.buttons["me.signOut"].waitForNonExistence(timeout: 5), "在「\(tab)」關閉之後「我的」還在")
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, "關閉「我的」之後沒有回到「\(tab)」")
        }
    }

    /// 五個 tab 的首頁沒有標題與副標題(#108):導覽列裡不再有大標題，tab bar 已經說明目前在哪個 tab。
    /// 總覽原本的標題是問候「早安，小明」,其他是「交易」「帳戶」「家庭」「統計」。
    @MainActor
    func testTabRootsHaveNoTitleOrSubtitle() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)

        for tab in ["總覽", "記帳", "帳戶", "家庭", "統計"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.buttons["toolbar.me"].waitForExistence(timeout: 5), "「\(tab)」主頁面沒有出現")

            let titles = app.navigationBars.staticTexts
            XCTAssertEqual(
                titles.count, 0,
                "「\(tab)」主頁面的導覽列還有標題或副標題:\(titles.allElementsBoundByIndex.map(\.label))"
            )
        }
    }

    /// VoiceOver 念「我的，姓名」。頭像上的字是姓名的第一個字，這個規則由 `AvatarInitialTests` 驗證
    /// (工具列按鈕會把裡面的字併進按鈕的 label,UI 測試查不到單獨的文字)。
    @MainActor
    func testAvatarIsLabelledForVoiceOver() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)

        let me = app.buttons["toolbar.me"]
        XCTAssertTrue(me.waitForExistence(timeout: 5), "總覽沒有頭像按鈕")
        XCTAssertEqual(me.label, "我的，小明", "頭像按鈕的 VoiceOver 標籤不對")
    }

}
