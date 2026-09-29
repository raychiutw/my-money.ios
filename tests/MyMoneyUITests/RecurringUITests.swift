import XCTest

/// 規劃 → 週期收支。資料來自 MyMoneyTestSupport 的 `InMemoryRecurringRepository.sample()`(不連網路)。
final class RecurringUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 統計卡與列表;新增一項後每月固定淨額跟著變;左滑刪除(先確認)。
    @MainActor
    func testSummaryAddAndDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["規劃"].tap()
        app.buttons["週期收支"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "每月固定淨額 31,000 元").waitForExistence(timeout: 5), "沒有看到統計卡")
        XCTAssertTrue(element(in: app, labelContaining: "每年 15 號扣款").exists, "扣款日沒有依週期描述")
        XCTAssertTrue(element(in: app, labelContaining: "年繳保費,週期支出 24,000 元").exists, "VoiceOver 沒有念出週期支出")
        XCTAssertTrue(element(in: app, labelContaining: "分攤平滑 2,000 元 / 月").exists, "年繳項目沒有顯示分攤平滑")

        app.buttons["recurring.add"].tap()
        let name = app.textFields["recurringEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("網路費")
        let amount = app.textFields["recurringEditor.amount"]
        amount.tap()
        amount.typeText("1000")
        app.buttons["recurringEditor.save"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "每月固定淨額 30,000 元").waitForExistence(timeout: 5), "新增後每月固定淨額沒有更新")

        let rent = element(in: app, labelContaining: "房租")
        rent.swipeLeft()
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["確定要刪除週期收支「房租」嗎？"].waitForExistence(timeout: 3), "沒有先確認就刪除")
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(rent.waitForNonExistence(timeout: 5), "刪除後還在列表上")
    }

    /// 編輯器的週期支出／週期收入在 sheet 導覽列中間(分段控制),表單裡沒有分段控制(#65)。
    /// 切到週期收入、新增每期 1,000 的項目，每月固定淨額從 31,000 變成 32,000。
    @MainActor
    func testEditorTypeInNavigationBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["規劃"].tap()
        app.buttons["週期收支"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "每月固定淨額 31,000 元").waitForExistence(timeout: 5), "沒有看到統計卡")

        app.buttons["recurring.add"].tap()
        let name = app.textFields["recurringEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3), "沒有打開週期收支編輯器")
        let type = app.navigationBars.segmentedControls.firstMatch
        XCTAssertTrue(type.exists, "週期支出／週期收入不在導覽列中間")
        XCTAssertTrue(type.buttons["週期支出"].isSelected, "新增週期收支預設不是週期支出")
        type.buttons["週期收入"].tap()
        let form = app.collectionViews.containing(.textField, identifier: "recurringEditor.name").firstMatch
        XCTAssertEqual(form.segmentedControls.count, 0, "週期收支編輯器的表單裡還有分段控制")

        name.tap()
        name.typeText("兼職")
        let amount = app.textFields["recurringEditor.amount"]
        amount.tap()
        amount.typeText("1000")
        app.buttons["recurringEditor.save"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "每月固定淨額 32,000 元").waitForExistence(timeout: 5), "新增週期收入後每月固定淨額沒有增加")
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
