import XCTest

/// 「總覽」tab。資料來自 MyMoneyTestSupport 的範例資料(日期相對於今天，不連網路)。
final class OverviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 從總覽記一筆 250 元 → 當月淨收支和最近交易跟著更新;「查看全部」進入交易 tab。
    @MainActor
    func testQuickEntryUpdatesMonthNetAndRecent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        // 範例：收入 45,000,支出 120 + 880(信用卡還款不算)。
        XCTAssertTrue(element(in: app, labelContaining: "當月淨收支 44,000 元").waitForExistence(timeout: 5), "沒有看到當月淨收支")
        XCTAssertTrue(element(in: app, labelContaining: "有 1 個分類支出已超出預算").exists, "沒有超支警示")

        app.buttons["overview.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("250")
        app.buttons["quickEntry.save"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "當月淨收支 43,750 元").waitForExistence(timeout: 5), "記一筆後當月淨收支沒有更新")
        // 最近交易在畫面下方;List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let recent = element(in: app, labelContaining: "支出 250 元")
        for _ in 0..<5 where !recent.exists { app.swipeUp() }
        XCTAssertTrue(recent.exists, "記一筆後最近交易沒有更新")

        let showAll = app.buttons["查看全部"]
        for _ in 0..<5 where !showAll.isHittable { app.swipeUp() }
        showAll.tap()
        XCTAssertTrue(app.buttons["transactions.add"].waitForExistence(timeout: 3), "「查看全部」沒有進入交易 tab")
    }

    /// 視角在 toolbar 的篩選按鈕(#63):點按鈕再選，導覽列副標題顯示目前的視角;選過的視角重開 app 之後沿用。
    @MainActor
    func testScopeFilterShowsSubtitleAndIsRemembered() throws {
        let app = launch(resettingSession: true)
        signIn(app)

        let filter = app.buttons["overview.scope"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "toolbar 沒有視角的篩選按鈕")
        XCTAssertEqual(filter.label, "視角", "篩選按鈕的 VoiceOver 標籤不是「視角」")
        XCTAssertEqual(filter.value as? String, "全部", "篩選按鈕的 VoiceOver 值不是目前的視角")
        XCTAssertTrue(subtitle("全部", in: app).waitForExistence(timeout: 3), "導覽列副標題沒有顯示目前的視角")

        choose("家庭", from: filter, in: app)
        XCTAssertTrue(element(in: app, labelContaining: "當月淨收支(家庭)").waitForExistence(timeout: 5), "切到家庭視角後，當月淨收支的標題沒有跟著變")
        XCTAssertTrue(subtitle("家庭", in: app).exists, "切換視角後導覽列副標題沒有跟著變")
        XCTAssertEqual(filter.value as? String, "家庭", "切換視角後篩選按鈕的 VoiceOver 值沒有跟著變")
        app.terminate()

        // 不帶 `-resetSession`:session 和選過的視角都還在。
        let relaunched = launch(resettingSession: false)
        XCTAssertTrue(subtitle("家庭", in: relaunched).waitForExistence(timeout: 5), "重開 app 之後沒有沿用選過的視角")
    }

    /// 點 toolbar 的篩選按鈕打開選單，再點選項。
    @MainActor
    private func choose(_ option: String, from filter: XCUIElement, in app: XCUIApplication) {
        filter.tap()
        let item = app.buttons[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "視角選單裡沒有「\(option)」")
        item.tap()
    }

    /// 導覽列副標題(`navigationSubtitle`)。
    @MainActor
    private func subtitle(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts[text]
    }

    @MainActor
    private func launch(resettingSession: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (resettingSession ? ["-resetSession"] : [])
        app.launch()
        return app
    }

    @MainActor
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
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
