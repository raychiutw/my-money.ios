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

        app.buttons["household.leave"].tap()
        XCTAssertTrue(
            app.staticTexts["確定要退出這個家庭群組嗎？退出後將無法查看這個家庭群組的家庭公帳。"].waitForExistence(timeout: 3),
            "沒有先確認就離開"
        )
        app.buttons["離開"].firstMatch.tap()
        XCTAssertTrue(app.textFields["household.createName"].waitForExistence(timeout: 5), "離開後沒有回到建立的畫面")
    }

    /// 替自己撥款報銷(#43):從家庭共同基金報銷自己的代墊款後，顯示後端的訊息，變成「已全數結清」。
    /// 範例帳號建立家庭群組後，有一筆用個人現金錢包墊付的晚餐 250(InMemoryHouseholdRepository.myPendingAdvance)。
    @MainActor
    func testReimburseMyOwnAdvance() throws {
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
        app.switches["accountEditor.jointFund"].switches.firstMatch.tap()
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
        app.buttons["household.reimburse"].tap()
        let submit = app.buttons["reimbursement.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 3), "沒有打開撥款報銷")
        submit.tap()

        XCTAssertTrue(element(in: app, labelContaining: "成功從共同基金撥款報銷 NT$ 250").waitForExistence(timeout: 5), "沒有顯示撥款報銷的結果")
        app.buttons["好"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "小明,已全數結清").waitForExistence(timeout: 5), "報銷後沒有結清")
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
