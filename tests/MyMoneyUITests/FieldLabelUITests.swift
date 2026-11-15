import XCTest

/// 欄位要有看得見的標籤(DESIGN.md「列與欄位」第 8 條，#157 逐頁 HIG 審查):
/// 備註欄不能只靠 placeholder——打了字、或 placeholder 消失之後，就不知道這一欄是什麼。
/// `LabeledContent("備註")` 的標籤是畫面上的靜態文字，所以查靜態文字「備註」。
final class FieldLabelUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuickEntryNoteHasVisibleLabel() {
        let app = launchSignedIn()
        app.buttons["overview.add"].tap()
        assertNoteLabel(in: app, field: "quickEntry.note", form: "記一筆")
    }

    @MainActor
    func testTransferNoteHasVisibleLabel() {
        let app = launchSignedIn()
        app.tabBars.buttons["帳戶"].tap()
        app.chooseFromAccountMenu("轉帳", accountID: "sample-bank")
        assertNoteLabel(in: app, field: "transfer.note", form: "轉帳")
    }

    @MainActor
    func testCardPaymentNoteHasVisibleLabel() {
        let app = launchSignedIn()
        app.tabBars.buttons["帳戶"].tap()
        let card = app.buttons["accounts.card.sample-card"]
        for _ in 0..<8 where !(card.exists && card.isHittable) { app.swipeUp() }
        card.tap()
        app.chooseFromDetailMenu("全額結清")
        assertNoteLabel(in: app, field: "cardPayment.note", form: "信用卡還款")
    }

    @MainActor
    func testReimbursementNoteHasVisibleLabel() {
        let app = launchSignedIn(extraArguments: ["-uiTestingJoinedHousehold"])
        app.tabBars.buttons["家庭"].tap()
        XCTAssertTrue(app.chooseMemberMenuItem("沖銷", memberID: "in-memory-member-1"), "自己的代墊詳細頁沒有報銷入口")
        assertNoteLabel(in: app, field: "reimbursement.note", form: "報銷")
    }

    @MainActor
    private func assertNoteLabel(in app: XCUIApplication, field: String, form: String) {
        let note = app.textFields[field]
        for _ in 0..<8 where !(note.exists && note.isHittable) { app.swipeUp() }
        XCTAssertTrue(note.exists, "\(form):沒有找到備註欄")
        // 輸入框方案 B:空的時候提示文字當標籤,打了字上方浮出小字「備註」。
        note.tap()
        note.typeText("午餐")
        XCTAssertTrue(app.staticTexts["備註"].waitForExistence(timeout: 3), "\(form):備註欄打了字之後沒有看得見的「備註」標籤")
    }

    @MainActor
    private func launchSignedIn(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"] + extraArguments
        app.launch()
        app.signInWithSampleAccount()
        return app
    }
}
