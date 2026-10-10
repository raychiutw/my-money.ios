import XCTest

/// 記一筆依備註自動預選分類(上游 ADR-0009,#99):輸入「中油加油」→ 分類預選「汽機車輛」並出現提示;
/// 手動改成別的分類之後，再改備註，分類就不會被覆蓋。資料來自 in-memory 範例(沒有歷史備註，所以走詞庫層)。
final class CategoryRecommendationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNotePreselectsCategoryAndManualChoiceLocksIt() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)
        app.tabBars.buttons["記帳"].tap()

        app.buttons["transactions.add"].tap()
        // 備註在金額正下方、分類格上面:打完金額就是備註，推薦提示緊貼在備註下面。
        let note = app.textFields["quickEntry.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "沒有打開記一筆")
        note.tap()
        note.typeText("中油加油")

        XCTAssertTrue(
            element(in: app, labelContaining: "智慧推薦為【汽機車輛】").waitForExistence(timeout: 3),
            "輸入備註後沒有出現分類的推薦提示"
        )
        app.buttons["完成"].tap()
        let fuel = categoryCell("汽機車輛", in: app)
        XCTAssertTrue(fuel.isSelected, "備註「中油加油」沒有把分類預選成汽機車輛")

        // 手動改選別的分類:鎖定，提示消失。
        let entertainment = categoryCell("娛樂", in: app)
        entertainment.tap()
        XCTAssertTrue(entertainment.isSelected, "點了娛樂沒有選取")
        XCTAssertTrue(
            element(in: app, labelContaining: "智慧推薦為").waitForNonExistence(timeout: 3),
            "手動選分類之後，推薦提示還在"
        )

        // 再改備註:分類不被覆蓋。
        for _ in 0..<4 where !(note.exists && note.isHittable) { app.swipeDown() }
        note.tap()
        note.typeText(" Netflix")
        app.buttons["完成"].tap()
        XCTAssertFalse(element(in: app, labelContaining: "智慧推薦為").exists, "鎖定之後改備註又出現推薦提示")
        XCTAssertTrue(categoryCell("娛樂", in: app).isSelected, "鎖定之後改備註，分類被覆蓋了")
    }

    /// 分類格的一格:表單是 collection view，tab bar 不是，所以不會抓到底部 tab bar 的按鈕。
    /// 格子不在畫面上時(被鍵盤或導覽列擋住)，往上捲到看得到為止。
    @MainActor
    private func categoryCell(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let cell = app.collectionViews.buttons[name]
        for _ in 0..<4 where !(cell.exists && cell.isHittable) { app.swipeDown() }
        return cell
    }

    @MainActor
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

}
