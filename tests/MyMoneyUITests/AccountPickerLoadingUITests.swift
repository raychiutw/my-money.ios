import XCTest

/// 帳戶選項是表單打開之後才載入的(#255):載入完成前點進選擇頁，會推出空白清單,而且推入時 `.task` 的載入被取消，
/// 清單要等返回才補上。所以載入完成前帳戶選擇列不能點。
///
/// `-uiTestingHoldAccountsAfter N`:前 N 次帳戶查詢照常(帳戶頁、總覽等已經載入完)，第 N + 1 次起停 30 秒——也就是表單內的那一次載入。
/// N 是進到表單之前 app 已經做過的帳戶查詢次數，換了進入的路徑就要重新量(見各測試的註解)。
final class AccountPickerLoadingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func picker(_ placeholder: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", placeholder)).firstMatch
    }

    @MainActor
    private func assertDisabled(_ placeholder: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let row = picker(placeholder, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "沒有「\(placeholder)」這一列", file: file, line: line)
        XCTAssertFalse(row.isEnabled, "帳戶還沒載入完，「\(placeholder)」不該能點(點了會推出空白清單)", file: file, line: line)
    }

    /// 轉帳:總覽與帳戶頁載入(2 次查詢)之後才打開表單(N = 2,量測值)。轉出、轉入兩列都停用。
    @MainActor
    func testTransferPickersAreDisabledUntilLoaded() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingHoldAccountsAfter", "2"], signedIn: true)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(app.buttons["accounts.card.sample-card"].waitForExistence(timeout: 10), "帳戶頁沒有載入完")
        app.chooseFromAccountMenu("轉帳", accountID: "sample-bank")
        XCTAssertTrue(app.textFields["transfer.amount"].waitForExistence(timeout: 5), "沒有打開轉帳")

        assertDisabled("請選擇轉出帳戶", in: app)
        assertDisabled("請選擇轉入帳戶", in: app)
    }

    /// 記一筆:總覽載入(1 次查詢)之後才打開表單(N = 1,量測值)。
    @MainActor
    func testQuickEntryAccountPickerIsDisabledUntilLoaded() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingHoldAccountsAfter", "1"], signedIn: true)
        app.tabBars.buttons["記帳"].tap()
        let add = app.buttons["transactions.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "記帳頁沒有「記一筆」")
        add.tap()
        XCTAssertTrue(app.textFields["quickEntry.amount"].waitForExistence(timeout: 5), "沒有打開記一筆")

        assertDisabled("請選擇扣款／存入帳戶", in: app)
    }

    /// 週期收支編輯:從首頁入口進週期收支頁之後才打開編輯器(N = 1,量測值)。關聯帳戶是選填(「無特定帳戶」),載入前也不能點。
    @MainActor
    func testRecurringEditorAccountPickerIsDisabledUntilLoaded() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingHoldAccountsAfter", "1"], signedIn: true)
        app.openHomeEntry("recurring")
        let add = app.buttons["recurring.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "週期收支頁沒有新增鈕")
        add.tap()
        XCTAssertTrue(app.textFields["recurringEditor.name"].waitForExistence(timeout: 5), "沒有打開編輯器")

        assertDisabled("關聯帳戶", in: app)
    }

    /// 報銷沖帳(N = 2,量測值):撥款公帳(家庭共同基金)要載入才有選項,所以停用;收款帳戶的選項來自代墊統計、不用另外載入，照常可點。
    @MainActor
    func testReimbursementFundPickerIsDisabledUntilLoaded() throws {
        let app = XCUIApplication.launchUITesting(
            flags: ["-uiTestingJoinedHousehold", "-uiTestingHoldAccountsAfter", "2"], signedIn: true
        )
        app.tabBars.buttons["家庭"].tap()
        let reimburse = app.openMemberDetail("sample-mei")
        XCTAssertTrue(reimburse.waitForExistence(timeout: 10), "小美的詳細頁沒有報銷入口")
        reimburse.tap()
        XCTAssertTrue(app.buttons["reimbursement.submit"].waitForExistence(timeout: 5), "沒有打開報銷沖帳")

        assertDisabled("請選擇家庭共同基金帳戶", in: app)
        let receiving = picker("請選擇收款個人帳戶", in: app)
        XCTAssertTrue(receiving.exists, "沒有收款帳戶這一列")
        XCTAssertTrue(receiving.isEnabled, "收款帳戶的選項不需要載入，不該被停用")
    }
}
