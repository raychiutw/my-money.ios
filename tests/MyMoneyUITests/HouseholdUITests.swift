import XCTest

/// 帳號 sheet → 家庭。資料來自 MyMoneyTestSupport 的 `InMemoryHouseholdRepository`(一開始沒有家庭群組，不連網路)。
final class HouseholdUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 建立家庭 → 我是管理員 → 邀請(複製後顯示「已複製」)→ 離開(先確認)→ 回到建立的畫面。
    @MainActor
    func testCreateInviteAndLeave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.buttons["overview.account"].tap()
        app.buttons["account.household"].tap()
        let name = app.textFields["household.createName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "沒有看到建立家庭")
        XCTAssertTrue(app.staticTexts["名稱"].exists, "家庭群組名稱欄沒有看得見的標籤")
        XCTAssertTrue(app.staticTexts["邀請碼"].exists, "邀請碼欄沒有看得見的標籤")
        XCTAssertFalse(app.buttons["household.create"].isEnabled, "名稱還沒填就能建立")
        name.tap()
        name.typeText("我們家")
        app.buttons["household.create"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "我的角色：管理員").waitForExistence(timeout: 5), "建立後沒有顯示家庭群組")

        app.buttons["household.invite"].tap()
        XCTAssertTrue(app.staticTexts["household.invitationCode"].waitForExistence(timeout: 3), "沒有顯示邀請碼")
        app.buttons["household.copy"].tap()
        XCTAssertTrue(app.buttons["已複製"].waitForExistence(timeout: 2), "複製後沒有顯示「已複製」")
        app.buttons["完成"].tap()

        // 「離開家庭群組」在代墊與報銷區塊下面;List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let leave = app.buttons["household.leave"]
        for _ in 0..<5 where !(leave.exists && leave.isHittable) { app.swipeUp() }
        leave.tap()
        XCTAssertTrue(
            app.staticTexts["確定要退出這個家庭群組嗎？退出後將無法查看這個家庭群組的家庭公帳。"].waitForExistence(timeout: 3),
            "沒有先確認就離開"
        )
        app.buttons["離開"].firstMatch.tap()
        XCTAssertTrue(app.textFields["household.createName"].waitForExistence(timeout: 5), "離開後沒有回到建立的畫面")
    }

    /// 替其他家庭成員撥款報銷(#47):範例帳號建立家庭群組後，小明和小美都有待報銷
    /// (InMemoryHouseholdRepository.myPendingAdvance、meiPendingAdvance),從共同基金撥給小美的可收款帳戶。
    @MainActor
    func testReimburseAnotherMembersAdvance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        // 先建立家庭共同基金(撥款帳戶)。
        app.tabBars.buttons["帳戶"].tap()
        app.buttons["accounts.add"].tap()
        app.buttons["新增銀行存款帳戶"].tap()
        let fundName = app.textFields["accountEditor.name"]
        XCTAssertTrue(fundName.waitForExistence(timeout: 3))
        fundName.tap()
        fundName.typeText("家庭共同基金")
        let fundAmount = app.textFields["accountEditor.amount"]
        fundAmount.tap()
        fundAmount.typeText("5000")
        // 歸屬選「家庭共同基金」(所有類型都一樣，跟 web 一樣)。sheet 底下帳戶檢視範圍的分段控制也有一個
        // 「家庭共同基金」,所以只找選單裡的選項(直接放在 cell 裡的按鈕)。
        app.buttons["accountEditor.jointFund"].tap()
        let jointFund = app.cells.children(matching: .button)["家庭共同基金"]
        XCTAssertTrue(jointFund.waitForExistence(timeout: 3), "歸屬沒有「家庭共同基金」這個選項")
        jointFund.tap()
        app.buttons["accountEditor.save"].tap()

        app.tabBars.buttons["總覽"].tap()
        app.buttons["overview.account"].tap()
        app.buttons["account.household"].tap()
        let name = app.textFields["household.createName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("我們家")
        app.buttons["household.create"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "小明,有待請款代墊").waitForExistence(timeout: 5), "沒有顯示我的代墊款")
        XCTAssertTrue(app.buttons["household.reimburse.in-memory-member-1"].exists, "自己的代墊款沒有報銷入口")
        let reimburseMei = app.buttons["household.reimburse.sample-mei"]
        for _ in 0..<5 where !reimburseMei.isHittable { app.swipeUp() }
        reimburseMei.tap()
        let submit = app.buttons["reimbursement.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 3), "沒有打開撥款報銷")
        XCTAssertTrue(element(in: app, labelContaining: "小美薪轉").exists, "收款帳戶不是小美的可收款帳戶")
        XCTAssertFalse(element(in: app, labelContaining: "(銀行存款帳戶)").exists, "帳戶選擇列的值還帶著類型")
        XCTAssertTrue(row("可用餘額", value: "5,000 元", in: app).exists, "撥款報銷沒有另起一列顯示撥款帳戶的可用餘額")
        submit.tap()

        XCTAssertTrue(element(in: app, labelContaining: "成功從共同基金撥款報銷 NT$ 600 給 小美").waitForExistence(timeout: 5), "沒有顯示撥款報銷的結果")
        app.buttons["好"].tap()
        let settled = element(in: app, labelContaining: "小美,已全數結清")
        for _ in 0..<5 where !settled.exists { app.swipeUp() }
        XCTAssertTrue(settled.exists, "報銷後沒有結清")
    }

    /// 撥款報銷：焦點在備註欄時，按鍵盤上的「完成」會收起鍵盤(#61)。
    /// 範例帳號建立家庭群組後，自己就有待報銷(InMemoryHouseholdRepository.myPendingAdvance)。
    @MainActor
    func testDoneOnReimbursementNoteDismissesKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.buttons["overview.account"].tap()
        app.buttons["account.household"].tap()
        let name = app.textFields["household.createName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("我們家")
        app.buttons["household.create"].tap()

        let reimburse = app.buttons["household.reimburse.in-memory-member-1"]
        XCTAssertTrue(reimburse.waitForExistence(timeout: 5), "自己的代墊款沒有報銷入口")
        for _ in 0..<5 where !reimburse.isHittable { app.swipeUp() }
        reimburse.tap()
        let note = app.textFields["reimbursement.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "沒有打開撥款報銷")
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "點備註欄後沒有出現鍵盤")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "備註欄按「完成」後，鍵盤沒有收起")
    }

    /// 一般列(`AmountRow`):VoiceOver 念標籤，值是金額。
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
