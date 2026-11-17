import XCTest

/// 記一筆的「帶入週期項目」(#361,上游 2631757):選單在表單第一區(類型之後、金額之前)，選了帶入金額與備註。
/// 資料來自 in-memory 範例(房租 12,000、家庭公帳)。
final class RecurringPresetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSelectingRecurringItemFillsAmountAndNote() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)
        app.tabBars.buttons["記帳"].tap()
        app.buttons["transactions.add"].tap()

        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開記一筆")
        let preset = app.buttons["quickEntry.recurringPreset"]
        XCTAssertTrue(preset.waitForExistence(timeout: 3), "記一筆沒有「帶入週期支出項目」選單")
        app.revealInQuickEntry(preset)
        preset.tap()
        let rent = app.buttons["[公帳] 房租 ($12,000)"]
        XCTAssertTrue(rent.waitForExistence(timeout: 3), "選單裡沒有「[公帳] 房租 ($12,000)」")
        rent.tap()

        let amountValue = (amount.value as? String ?? "").filter(\.isNumber)
        XCTAssertEqual(amountValue, "12000", "選了房租沒有帶入金額")
        XCTAssertEqual(app.textFields["quickEntry.note"].value as? String, "房租", "選了房租沒有帶入備註")
    }
}
