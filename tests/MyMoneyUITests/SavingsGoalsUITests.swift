import XCTest

/// 規劃 → 儲蓄目標。資料來自 MyMoneyTestSupport 的 `InMemorySavingsGoalRepository.sample()`(不連網路)。
final class SavingsGoalsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 統計卡與已達成的目標;存入後已存金額合計更新;建立新目標後目標金額合計更新。
    @MainActor
    func testSummaryDepositAndCreate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["規劃"].tap()
        app.buttons["儲蓄目標"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "已存金額合計 4,000 元").waitForExistence(timeout: 5), "沒有看到統計卡")
        XCTAssertTrue(row("整體達成率", value: "2.5%", in: app).exists, "整體達成率不是一般列")
        XCTAssertTrue(
            element(in: app, labelContaining: "沖繩旅遊，已存 3,000 元，目標 60,000 元，達成 5%").exists,
            "目標列沒有把已存、目標、達成百分比念成一句"
        )
        XCTAssertTrue(element(in: app, labelContaining: "已達成目標").exists, "已達成的目標沒有標示")

        app.buttons["goals.deposit.sample-trip"].tap()
        XCTAssertTrue(app.staticTexts["目前已存 $3,000 / 目標 $60,000"].waitForExistence(timeout: 3), "存入 sheet 沒有顯示目前進度")
        let amount = app.textFields["goalDeposit.amount"]
        amount.tap()
        amount.typeText("2000")
        app.buttons["goalDeposit.save"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "已存金額合計 6,000 元").waitForExistence(timeout: 5), "存入後已存金額合計沒有更新")

        app.buttons["goals.add"].tap()
        let name = app.textFields["goalEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("買新筆電")
        let target = app.textFields["goalEditor.target"]
        target.tap()
        target.typeText("45000")
        app.buttons["goalEditor.save"].tap()
        XCTAssertTrue(row("目標金額合計", value: "206,000 元", in: app).waitForExistence(timeout: 5), "建立後目標金額合計沒有更新")
    }

    /// 摘要的一般列(`AmountRow` 或 `LabeledContent`):VoiceOver 念標籤，值是金額或百分比。
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
