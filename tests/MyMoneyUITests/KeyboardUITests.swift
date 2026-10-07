import XCTest

/// 鍵盤彈出時:取得焦點的欄位不能被鍵盤、也不能被鍵盤上方浮著的「完成」鈕蓋住。
/// 一般字級與無障礙字級(AX5)各跑一輪;欄位的 `frame` 底邊必須在「完成」鈕上緣(沒有就是鍵盤上緣)之上。
final class KeyboardUITests: XCTestCase {
    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    private var sizeName = "一般字級"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: 每個表單

    @MainActor func testForecastPurchaseAmount() throws { try forEachSize { app in
        app.openHomeEntry("forecast")
        try self.assertClear(app.textFields["forecast.purchaseAmount"], app: app, inSheet: false)
    } }

    @MainActor func testQuickEntryFields() throws { try forEachSize { app in
        app.buttons["overview.add"].tap()
        try self.assertClear(app.textFields["quickEntry.amount"], app: app)
        try self.assertClear(app.descendants(matching: .any)["quickEntry.note"], app: app)
    } }

    @MainActor func testTransferFields() throws { try forEachSize { app in
        app.tabBars.buttons["帳戶"].tap()
        let transfer = app.buttons["accounts.transfer"]
        XCTAssertTrue(ScrollSupport.revealFully(transfer, in: app))
        transfer.tap()
        try self.assertClear(app.textFields["transfer.amount"], app: app)
        try self.assertClear(app.descendants(matching: .any)["transfer.note"], app: app)
    } }

    @MainActor func testCardPaymentFields() throws { try forEachSize { app in
        app.tabBars.buttons["帳戶"].tap()
        let card = app.buttons["accounts.card.sample-card"]
        XCTAssertTrue(ScrollSupport.revealFully(card, in: app))
        card.tap()
        let pay = app.buttons["cardDetail.pay"]
        XCTAssertTrue(ScrollSupport.revealFully(pay, in: app))
        pay.tap()
        app.buttons["全額結清"].tap()
        try self.assertClear(app.textFields["cardPayment.amount"], app: app)
        try self.assertClear(app.descendants(matching: .any)["cardPayment.note"], app: app)
    } }

    @MainActor func testReimbursementFields() throws { try forEachSize(extra: ["-uiTestingJoinedHousehold"]) { app in
        app.tabBars.buttons["家庭"].tap()
        let reimburse = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "household.reimburse.")).firstMatch
        XCTAssertTrue(ScrollSupport.revealFully(reimburse, in: app))
        reimburse.tap()
        try self.assertClear(app.textFields["reimbursement.amount"], app: app)
        try self.assertClear(app.descendants(matching: .any)["reimbursement.note"], app: app)
    } }

    @MainActor func testGoalDepositAmount() throws { try forEachSize { app in
        app.openHomeEntry("goals")
        let deposit = app.buttons["goals.deposit.sample-trip"]
        XCTAssertTrue(ScrollSupport.revealFully(deposit, in: app))
        deposit.tap()
        try self.assertClear(app.textFields["goalDeposit.amount"], app: app)
    } }

    @MainActor func testGoalEditorFields() throws { try forEachSize { app in
        app.openHomeEntry("goals")
        app.buttons["goals.add"].tap()
        try self.assertClear(app.textFields["goalEditor.name"], app: app)
        try self.assertClear(app.textFields["goalEditor.target"], app: app)
        try self.assertClear(app.textFields["goalEditor.reserve"], app: app)
    } }

    @MainActor func testBudgetEditorAmount() throws { try forEachSize { app in
        app.tabBars.buttons["統計"].tap()
        let add = app.buttons["budgets.add"]
        XCTAssertTrue(ScrollSupport.revealFully(add, in: app))
        add.tap()
        try self.assertClear(app.textFields["budgetEditor.amount"], app: app)
    } }

    @MainActor func testRecurringEditorFields() throws { try forEachSize { app in
        app.openHomeEntry("recurring")
        app.buttons["recurring.add"].tap()
        try self.assertClear(app.textFields["recurringEditor.name"], app: app)
        try self.assertClear(app.textFields["recurringEditor.amount"], app: app)
    } }

    @MainActor func testCashAccountEditorFields() throws { try forEachSize { app in
        app.tabBars.buttons["帳戶"].tap()
        app.buttons["accounts.add"].tap()
        app.buttons["新增現金"].tap()
        try self.assertClear(app.textFields["accountEditor.name"], app: app)
        try self.assertClear(app.textFields["accountEditor.amount"], app: app)
    } }

    @MainActor func testCreditCardEditorFields() throws { try forEachSize { app in
        app.tabBars.buttons["帳戶"].tap()
        app.buttons["accounts.add"].tap()
        app.buttons["新增信用卡"].tap()
        try self.assertClear(app.textFields["accountEditor.unbilled"], app: app)
        try self.assertClear(app.textFields["accountEditor.creditLimit"], app: app)
    } }

    @MainActor func testHouseholdCreateAndJoinFields() throws { try forEachSize { app in
        app.tabBars.buttons["家庭"].tap()
        try self.assertClear(app.textFields["household.createName"], app: app, inSheet: false)
        try self.assertClear(app.textFields["household.joinCode"], app: app, inSheet: false)
    } }

    // MARK: 流程與量測

    /// 一般字級與 AX5 各啟動一次,登入後跑 `body`。
    @MainActor
    private func forEachSize(extra: [String] = [], _ body: (XCUIApplication) throws -> Void) throws {
        for size in [nil, Self.ax5] as [String?] {
            sizeName = size == nil ? "一般字級" : "AX5"
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-resetSession"] + extra
                + (size.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
            app.launch()
            app.signInWithSampleAccount()
            try body(app)
            app.terminate()
        }
    }

    /// 捲到欄位、點它取得焦點,再確認它的底邊在「完成」鈕(沒有就是鍵盤)的上緣之上至少 8pt、頂邊在導覽列之下。
    @MainActor
    private func assertClear(_ field: XCUIElement, app: XCUIApplication, inSheet: Bool = true, line: UInt = #line) throws {
        XCTAssertTrue(ScrollSupport.revealFully(field, in: app, inSheet: inSheet), "找不到或捲不到 \(field.identifier)", line: line)
        field.tap()
        let keyboard = app.keyboards.firstMatch
        if !keyboard.waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "no keyboard \(field.identifier) \(sizeName)"
            shot.lifetime = .keepAlways
            add(shot)
            XCTFail("[\(sizeName)] \(field.identifier) 點了沒有鍵盤,欄位 \(field.frame)", line: line)
            return
        }
        // 工具列的「完成」鈕有進場動畫;等它出現且位置穩定。
        let done = app.buttons["完成"].firstMatch
        _ = done.waitForExistence(timeout: 2)
        Thread.sleep(forTimeInterval: 1.0)
        let limit = done.exists && done.frame.minY < keyboard.frame.minY ? done.frame.minY : keyboard.frame.minY
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(field.identifier) \(sizeName)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThanOrEqual(
            field.frame.maxY, limit - 8,
            "[\(sizeName)] \(field.identifier) 被鍵盤或「完成」鈕蓋住:欄位 \(field.frame),完成 \(done.frame),鍵盤 \(keyboard.frame)", line: line
        )
        // 收起鍵盤,下一個欄位重新來。
        if done.exists { done.tap() }
        Thread.sleep(forTimeInterval: 0.5)
    }
}
