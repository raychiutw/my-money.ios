import XCTest

/// 日期選定就收起(#272):compact 日期選擇器的彈出日曆選完日期要自己關掉,不必再點外面。
final class DatePickerDismissUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testQuickEntryDatePopoverClosesAfterPickingDay() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)
        app.buttons["overview.add"].tap()
        XCTAssertTrue(app.navigationBars.buttons["關閉"].firstMatch.waitForExistence(timeout: 8), "沒有打開「記一筆」表單")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "日期")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        // 彈出的日曆:月份標題的按鈕還在,表示日曆開著。
        let calendar = app.datePickers.firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 3))
        let day = app.datePickers.collectionViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", "日")).element(boundBy: 3)
        XCTAssertTrue(day.waitForExistence(timeout: 3), app.debugDescription)
        day.tap()
        let closed = NSPredicate(format: "exists == false")
        expectation(for: closed, evaluatedWith: app.datePickers.collectionViews.firstMatch)
        waitForExpectations(timeout: 3)
    }
}
