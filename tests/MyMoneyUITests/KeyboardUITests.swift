import UIKit
import XCTest

/// 鍵盤彈出時:取得焦點的欄位不能被鍵盤、也不能被鍵盤上方浮著的「完成」鈕蓋住。
/// 一般字級與無障礙字級(AX5)各跑一輪;欄位的 `frame` 底邊必須在「完成」鈕上緣(沒有就是鍵盤上緣)之上。
final class KeyboardUITests: XCTestCase {
    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    private var sizeName = "一般字級"
    private var orientationName = "直向"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: 每個表單

    @MainActor func testForecastPurchaseAmount() throws { try forEachSize(landscape: true) { app in
        app.openHomeEntry("forecast")
        try self.assertClear(app.textFields["forecast.purchaseAmount"], app: app, inSheet: false)
    } }

    @MainActor func testQuickEntryFields() throws { try forEachSize { app in
        app.buttons["overview.add"].tap()
        try self.assertClear(app.textFields["quickEntry.amount"], app: app)
        try self.assertClear(app.descendants(matching: .any)["quickEntry.note"], app: app)
    } }

    @MainActor func testTransferFields() throws { try forEachSize { app in
        self.selectTab("帳戶", in: app)
        let transfer = app.buttons["accounts.transfer"]
        XCTAssertTrue(ScrollSupport.revealFully(transfer, in: app))
        transfer.tap()
        try self.assertClear(app.textFields["transfer.amount"], app: app)
        try self.assertClear(app.descendants(matching: .any)["transfer.note"], app: app)
    } }

    @MainActor func testCardPaymentFields() throws { try forEachSize { app in
        self.selectTab("帳戶", in: app)
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
        self.selectTab("家庭", in: app)
        // 小美的待報銷沒有代墊明細，仍是手動輸入金額;自己的有明細，金額由勾選連動(沒有輸入框，#242)。
        let reimburse = app.buttons["household.reimburse.sample-mei"]
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
        self.selectTab("統計", in: app)
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
        self.selectTab("帳戶", in: app)
        app.buttons["accounts.add"].tap()
        app.buttons["新增現金"].tap()
        try self.assertClear(app.textFields["accountEditor.name"], app: app)
        try self.assertClear(app.textFields["accountEditor.amount"], app: app)
    } }

    @MainActor func testCreditCardEditorFields() throws { try forEachSize { app in
        self.selectTab("帳戶", in: app)
        app.buttons["accounts.add"].tap()
        app.buttons["新增信用卡"].tap()
        try self.assertClear(app.textFields["accountEditor.unbilled"], app: app)
        try self.assertClear(app.textFields["accountEditor.creditLimit"], app: app)
    } }

    @MainActor func testHouseholdCreateAndJoinFields() throws { try forEachSize(landscape: true) { app in
        self.selectTab("家庭", in: app)
        try self.assertClear(app.textFields["household.createName"], app: app, inSheet: false)
        try self.assertClear(app.textFields["household.joinCode"], app: app, inSheet: false)
    } }

    // MARK: 流程與量測

    /// 元素存在而且點得到;逾時回傳 `false`,不記錄失敗。
    @MainActor
    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// iPhone 的 tab 在底部 tab bar;iPad 在頂端或側邊(sidebarAdaptable),不一定在 `tabBars` 裡:用標籤或圖示的 identifier 找(同 `IPadLayoutUITests`)。
    @MainActor
    private func selectTab(_ tab: String, in app: XCUIApplication) {
        let symbols = ["總覽": "house", "記帳": "list.bullet.rectangle", "帳戶": "creditcard", "家庭": "person.2", "統計": "chart.bar"]
        let candidates = [
            app.tabBars.buttons[tab], app.buttons[symbols[tab] ?? tab].firstMatch, app.buttons[tab].firstMatch, app.cells[tab].firstMatch,
        ]
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !candidates.contains(where: \.exists) { Thread.sleep(forTimeInterval: 0.25) }
        guard let button = candidates.first(where: \.exists) else { return XCTFail("找不到 tab「\(tab)」") }
        button.tap()
    }

    /// 一般字級與 AX5 各啟動一次,登入後跑 `body`。
    /// iPad 另外跑橫向(#200),但只有 `landscape: true` 的表單:橫向的 sheet 是置中的矮卡片,旋轉後清單重建,
    /// UI 測試讀不到 sheet 裡的欄位(輔助的限制,不是已證實的版面問題),這些表單的橫向列在 PR 的手動驗收清單。
    @MainActor
    private func forEachSize(extra: [String] = [], landscape: Bool = false, _ body: (XCUIApplication) throws -> Void) throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let orientations: [(UIDeviceOrientation, String)] = isPad && landscape ? [(.portrait, "直向"), (.landscapeLeft, "橫向")] : [(.portrait, "直向")]
        for (orientation, orientationLabel) in orientations {
            for size in [nil, Self.ax5] as [String?] {
                XCUIDevice.shared.orientation = orientation
                orientationName = orientationLabel
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
    }

    /// 捲到欄位、點它取得焦點,再確認它的底邊在「完成」鈕(沒有就是鍵盤)的上緣之上至少 8pt、頂邊在導覽列之下。
    @MainActor
    private func assertClear(_ field: XCUIElement, app: XCUIApplication, inSheet: Bool = true, line: UInt = #line) throws {
        // 已經點得到(iPad 的 sheet 是置中卡片,欄位通常已在畫面內)就不捲動;否則捲到整個看得到。
        // 用 predicate 等待:iPad 橫向旋轉後清單會重建,直接讀 `isHittable` 遇到剛消失的元素會記成失敗。
        if !waitHittable(field, timeout: 3) {
            let window = app.windows.firstMatch.frame
            if UIDevice.current.userInterfaceIdiom == .pad, inSheet, window.width > window.height {
                // iPad 橫向的 sheet 是置中的矮卡片:直接對最上層的清單往上滑,不靠視窗座標的拖曳(直向沿用 `ScrollSupport`)。
                for _ in 0..<10 where !waitHittable(field, timeout: 0.5) {
                    app.collectionViews.allElementsBoundByIndex.last?.swipeUp(velocity: .slow)
                }
                if !waitHittable(field, timeout: 1) {
                    let shot = XCTAttachment(screenshot: app.screenshot())
                    shot.name = "找不到 \(field.identifier) \(orientationName) \(sizeName)"
                    shot.lifetime = .keepAlways
                    add(shot)
                    XCTFail("[\(orientationName)・\(sizeName)] 找不到或捲不到 \(field.identifier)", line: line)
                    return
                }
            } else {
                XCTAssertTrue(ScrollSupport.revealFully(field, in: app, inSheet: inSheet), "找不到或捲不到 \(field.identifier)", line: line)
            }
        }
        field.tap()
        let keyboard = app.keyboards.firstMatch
        if !keyboard.waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "no keyboard \(field.identifier) \(orientationName) \(sizeName)"
            shot.lifetime = .keepAlways
            add(shot)
            XCTFail("[\(orientationName)・\(sizeName)] \(field.identifier) 點了沒有鍵盤,欄位 \(field.frame)", line: line)
            return
        }
        // 工具列的「完成」鈕有進場動畫;等它出現且位置穩定。
        let done = app.buttons["完成"].firstMatch
        _ = done.waitForExistence(timeout: 2)
        Thread.sleep(forTimeInterval: 1.0)
        let limit = done.exists && done.frame.minY < keyboard.frame.minY ? done.frame.minY : keyboard.frame.minY
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(field.identifier) \(orientationName) \(sizeName)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThanOrEqual(
            field.frame.maxY, limit - 8,
            "[\(orientationName)・\(sizeName)] \(field.identifier) 被鍵盤或「完成」鈕蓋住:欄位 \(field.frame),完成 \(done.frame),鍵盤 \(keyboard.frame)", line: line
        )
        // 收起鍵盤,下一個欄位重新來。
        if done.exists { done.tap() }
        Thread.sleep(forTimeInterval: 0.5)
    }
}
