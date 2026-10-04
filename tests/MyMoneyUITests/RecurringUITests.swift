import XCTest

/// 規劃 → 週期收支。資料來自 MyMoneyTestSupport 的 `InMemoryRecurringRepository.sample()`(不連網路)。
final class RecurringUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 統計卡與列表;新增一項後每月週期淨額跟著變;左滑刪除(先確認)。
    @MainActor
    func testSummaryAddAndDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.openHomeEntry("recurring")
        XCTAssertTrue(row("每月週期淨額", value: "31,000 元", in: app).waitForExistence(timeout: 5), "沒有看到摘要")
        XCTAssertTrue(element(in: app, labelContaining: "週期支出每月平均 14,000 元").exists, "摘要的主數字不是週期支出每月平均")
        XCTAssertTrue(element(in: app, labelContaining: "每年 1 月 15 號扣款").exists, "扣款日沒有依週期描述(舊資料的繳費月份是 1)")
        XCTAssertTrue(element(in: app, labelContaining: "年繳保費，週期支出 24,000 元").exists, "VoiceOver 沒有把週期支出念成一句")
        XCTAssertTrue(element(in: app, labelContaining: "換算每月平均 2,000 元").exists, "年繳項目沒有顯示每月平均")
        XCTAssertFalse(element(in: app, labelContaining: "未指定關聯帳戶").exists, "沒設帳戶時不該顯示「未指定關聯帳戶」")

        app.buttons["recurring.add"].tap()
        let name = app.textFields["recurringEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["名稱"].exists, "週期收支編輯器的名稱欄沒有看得見的標籤")
        name.tap()
        name.typeText("網路費")
        let amount = app.textFields["recurringEditor.amount"]
        amount.tap()
        amount.typeText("1000")
        app.buttons["recurringEditor.save"].tap()
        XCTAssertTrue(row("每月週期淨額", value: "30,000 元", in: app).waitForExistence(timeout: 5), "新增後每月週期淨額沒有更新")

        let rent = element(in: app, labelContaining: "房租")
        rent.swipeLeft()
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["確定要刪除週期收支「房租」嗎？"].waitForExistence(timeout: 3), "沒有先確認就刪除")
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(rent.waitForNonExistence(timeout: 5), "刪除後還在列表上")
    }

    /// 繳費月份(上游 `feabed3`，#131):選季繳才出現月份選項，選了「2、5、8、11 月」儲存後，卡片寫確切時程;
    /// 切回月繳月份欄位消失。
    @MainActor
    func testQuarterlyMonthChoiceShowsExactScheduleOnTheCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.openHomeEntry("recurring")

        app.buttons["recurring.add"].tap()
        let name = app.textFields["recurringEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3), "沒有打開週期收支編輯器")
        let month = app.descendants(matching: .any)["recurringEditor.month"]
        XCTAssertFalse(month.exists, "月繳不該有月份欄位")

        name.tap()
        name.typeText("保險費")
        let amount = app.textFields["recurringEditor.amount"]
        amount.tap()
        amount.typeText("3000")
        app.buttons["完成"].firstMatch.tap()
        let quarterly = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "每季")).firstMatch
        for _ in 0..<4 where !(quarterly.exists && quarterly.isHittable) { app.swipeUp() }
        quarterly.tap()
        let second = app.buttons["2、5、8、11 月"]
        for _ in 0..<4 where !(second.exists && second.isHittable) { app.swipeUp() }
        XCTAssertTrue(second.exists, "選了季繳之後沒有出現月份選項")
        XCTAssertTrue(app.buttons["1、4、7、10 月"].exists && app.buttons["3、6、9、12 月"].exists, "季繳的月份選項不是 3 組")
        second.tap()
        app.buttons["recurringEditor.save"].tap()

        XCTAssertTrue(
            element(in: app, labelContaining: "保險費，週期支出 3,000 元，每季 (2/5/8/11月) 1 號扣款").waitForExistence(timeout: 5),
            "卡片沒有寫出確切時程(扣款日預設 1 號)"
        )
    }

    /// 編輯器的週期支出／週期收入在 sheet 導覽列中間(分段控制),表單裡沒有分段控制(#65)。
    /// 切到週期收入、新增每期 1,000 的項目，每月週期淨額從 31,000 變成 32,000。
    @MainActor
    func testEditorTypeInNavigationBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.openHomeEntry("recurring")
        XCTAssertTrue(row("每月週期淨額", value: "31,000 元", in: app).waitForExistence(timeout: 5), "沒有看到摘要")

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
        XCTAssertTrue(row("每月週期淨額", value: "32,000 元", in: app).waitForExistence(timeout: 5), "新增週期收入後每月週期淨額沒有增加")
    }

    /// 週期是內嵌選擇列(5 列，點一下就選);扣款日(1～31 號)推入清單頁，選了自動返回(ADR-0004、#91)。
    @MainActor
    func testCycleIsInlineAndDayIsAPushedList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.openHomeEntry("recurring")
        app.buttons["recurring.add"].tap()
        XCTAssertTrue(app.textFields["recurringEditor.name"].waitForExistence(timeout: 3), "沒有打開週期收支編輯器")

        XCTAssertTrue(app.buttons["每月"].exists, "週期缺少「每月」這一列")
        XCTAssertTrue(app.buttons["每月"].isSelected, "新增週期收支預設的週期不是每月")
        let quarterly = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "每季")).firstMatch
        XCTAssertTrue(quarterly.exists, "週期缺少「每季」這一列")
        quarterly.tap()
        XCTAssertTrue(quarterly.isSelected, "點一下每季之後沒有選起來")

        func dayRow() -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "扣款日")).firstMatch
        }
        XCTAssertTrue(dayRow().exists, "沒有「扣款日」列")
        dayRow().tap()
        let fifth = app.buttons["5 號"]
        XCTAssertTrue(fifth.waitForExistence(timeout: 3), "點了扣款日沒有推入日期清單頁")
        fifth.tap()
        XCTAssertTrue(dayRow().waitForExistence(timeout: 3), "選了日期之後沒有自動返回")
        XCTAssertTrue(dayRow().displayedText.contains("5 號"), "返回之後扣款日不是 5 號:\(dayRow().displayedText)")
    }

    /// 摘要的一般列(`AmountRow`):VoiceOver 念標籤，值是金額。
    @MainActor
    private func row(_ label: String, value: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", label, value)).firstMatch
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
