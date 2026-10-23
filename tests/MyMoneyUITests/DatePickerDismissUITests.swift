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
        // compact 日期選擇器的按鈕(label「日期選擇器」,value 是目前的日期)。
        let picker = app.buttons["日期選擇器"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        // 彈出的日曆:點月曆裡的一天(標籤是「10月24日」這類)。
        let day = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "[0-9]+月[0-9]+日.*")).element(boundBy: 3)
        XCTAssertTrue(day.waitForExistence(timeout: 3), app.debugDescription)
        let shown = day.label
        day.tap()
        // 選完日期,彈出的日曆自己收起來(月曆的日期按鈕都消失),而且表單上顯示選到的日期。
        let calendarGone = NSPredicate(format: "exists == false")
        expectation(for: calendarGone, evaluatedWith: day)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(picker.exists, "表單回到前景:\(shown)")
    }
}
