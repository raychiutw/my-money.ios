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
    func testLoginFieldsHaveVisibleLabels() {
        let app = launchSignedOut()
        XCTAssertTrue(app.textFields["login.email"].waitForExistence(timeout: 5), "沒有看到登入頁")
        for label in ["電子郵件", "密碼"] {
            XCTAssertTrue(app.staticTexts[label].exists, "登入頁的欄位沒有看得見的「\(label)」標籤，只有 placeholder")
        }
    }

    @MainActor
    func testRegisterFieldsHaveVisibleLabels() {
        let app = launchSignedOut()
        app.buttons["login.register"].tap()
        XCTAssertTrue(app.textFields["register.name"].waitForExistence(timeout: 5), "沒有看到註冊頁")
        for label in ["姓名", "電子郵件", "密碼", "確認密碼"] {
            XCTAssertTrue(app.staticTexts[label].exists, "註冊頁的欄位沒有看得見的「\(label)」標籤，只有 placeholder")
        }
    }

    /// 無障礙字級下標籤在欄位上方，點標籤(整列的上半)也要能開始輸入;不然點整列的正中央會落在標籤上，欄位沒有焦點。
    @MainActor
    func testTappingTheLabelFocusesTheFieldAtAccessibilitySize() {
        let app = launchSignedOut(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(app.textFields["login.email"].waitForExistence(timeout: 5), "沒有看到登入頁")
        app.staticTexts["電子郵件"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "點「電子郵件」標籤沒有開始輸入")
        app.textFields["login.email"].typeText("a@b.c")
        XCTAssertEqual(app.textFields["login.email"].value as? String, "a@b.c")
    }

    @MainActor
    private func launchSignedOut(contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        return app
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
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "登入後沒有進入 tab 外殼")
        return app
    }
}
