import XCTest

/// 明細卡(#280,方案 B):金額固定在同一條右側欄位、垂直對齊——有 ⋯ 的列(可編輯)與沒有 ⋯ 的列(系統紀錄、家人記的)一樣;
/// 時間、記帳人、帳戶各占一行,不連成一排。
final class EntryCardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 記帳頁每一列的金額右緣是同一個位置(以前有 ⋯ 的列被擠左,沒有 ⋯ 的列貼最右)。
    @MainActor
    func testAmountsShareOneRightEdgeWhetherOrNotTheRowHasMoreMenu() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingLongRows", "-uiTestingRowParts"], signedIn: true)
        app.tabBars.buttons["記帳"].tap()
        let window = app.windows.firstMatch.frame
        var edges: [CGFloat] = []
        for pass in 0..<4 {
            let amounts = app.descendants(matching: .any).matching(identifier: "row.amount").allElementsBoundByIndex
            for amount in amounts where amount.exists && amount.frame.minY > window.minY + 120 && amount.frame.maxY < window.maxY - 90 {
                edges.append(amount.frame.maxX)
            }
            if pass < 3 { app.swipeUp() }
        }
        XCTAssertGreaterThan(edges.count, 4, "沒有量到足夠的列")
        let minEdge = try XCTUnwrap(edges.min()), maxEdge = try XCTUnwrap(edges.max())
        XCTAssertLessThanOrEqual(maxEdge - minEdge, 1, "金額右緣不一致:\(Set(edges.map { Int($0) }).sorted())")
    }

    /// 時間、記帳人、帳戶各占一行(三個元素的垂直位置由上而下、互不重疊),不連成一排。
    @MainActor
    func testTimeRecorderAndAccountAreSeparateLines() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingRowParts"], signedIn: true)
        app.tabBars.buttons["記帳"].tap()
        let time = app.descendants(matching: .any).matching(identifier: "row.time").firstMatch
        XCTAssertTrue(time.waitForExistence(timeout: 8), "沒有時間那一行")
        let recorder = app.descendants(matching: .any).matching(identifier: "row.recorder").firstMatch
        let account = app.descendants(matching: .any).matching(identifier: "row.account").firstMatch
        XCTAssertTrue(recorder.exists && account.exists, "缺記帳人或帳戶那一行")
        XCTAssertLessThanOrEqual(time.frame.maxY, recorder.frame.minY + 1, "時間與記帳人不在不同行:\(time.frame) \(recorder.frame)")
        XCTAssertLessThanOrEqual(recorder.frame.maxY, account.frame.minY + 1, "記帳人與帳戶不在不同行:\(recorder.frame) \(account.frame)")
        XCTAssertEqual(time.frame.minX, account.frame.minX, accuracy: 1, "三行的左緣要一致")
    }
}
