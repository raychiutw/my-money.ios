import UIKit
import XCTest

/// 畫面上的字不能被截成「…」(#157 逐頁 HIG 審查):字級放大後放不下要改版面(換行、堆疊、少放幾個刻度)，不是截斷。
/// accessibility 只看得到完整的 label，看不到畫面上實際寫了什麼，所以用 OCR 驗證「看得到的字」。
final class TruncationUITests: XCTestCase {
    private static let xxl = "UICTContentSizeCategoryXXL"
    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: 總覽的功能入口:關鍵數字長(預測的最低餘額與日期、儲蓄目標)，大字級要折行，不能截成「…」

    @MainActor
    func testEntryValuesAreNotTruncatedAtAccessibilitySize() throws {
        let app = launchSignedIn(contentSize: Self.ax5)
        for (id, expected) in [("forecast", "最低"), ("goals", "已存")] {
            let entry = app.buttons["home.entry.\(id)"]
            XCTAssertTrue(ScrollSupport.revealFully(entry, in: app), "總覽沒有找到「\(id)」入口")
            let lines = try TextRecognition.lines(in: entry.screenshot().image)
            XCTAssertTrue(lines.contains { $0.contains(expected) }, "「\(id)」入口看不到關鍵數字(預期有「\(expected)」),辨識到:\(lines)")
            XCTAssertFalse(lines.contains { Self.isTruncated($0) }, "「\(id)」入口的字被截斷:\(lines)")
        }
    }

    // MARK: 總覽的帳戶卡:名稱完整折行,不能截成「iOS 測試…」(#162)

    @MainActor
    func testAccountCardNamesAreNotTruncatedAtAccessibilitySize() throws {
        let app = launchSignedIn(contentSize: Self.ax5)
        let first = app.buttons["overview.card.sample-bank"]
        XCTAssertTrue(ScrollSupport.revealFully(first, in: app), "總覽沒有找到第一張帳戶卡")
        let window = app.windows.firstMatch.frame
        // 往左撥要用「那一排」的位置:撥動之後第一張卡已經在畫面外，不能再對它操作。
        let rowY = (first.frame.midY - window.minY) / window.height
        func swipeLeftOnRow() {
            let from = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: rowY))
            let to = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: rowY))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        for (id, name) in [("sample-bank", "測試存款"), ("sample-card", "測試信用卡"), ("sample-low-limit-card", "測試小額卡")] {
            let card = app.buttons["overview.card.\(id)"]
            // 帳戶卡橫向捲動:無障礙字級一張卡幾乎整個畫面寬,要往左撥到整張卡都在畫面裡。
            for _ in 0..<6 where !(card.exists && card.frame.minX >= 0 && card.frame.maxX <= window.maxX) {
                swipeLeftOnRow()
            }
            XCTAssertTrue(card.exists && card.frame.maxX <= window.maxX, "帳戶卡「\(id)」撥不進畫面:\(card.frame)")
            let lines = try TextRecognition.lines(in: card.screenshot().image)
            let text = lines.joined().replacingOccurrences(of: " ", with: "")
            XCTAssertTrue(text.contains(name), "帳戶卡「\(id)」看不到完整名稱「\(name)」,辨識到:\(lines)")
            XCTAssertFalse(lines.contains { Self.isTruncated($0) }, "帳戶卡「\(id)」的名稱被截斷:\(lines)")
        }
    }

    // MARK: 現金流預測圖的日期刻度(無障礙字級系統自己會少放刻度，舊程式也沒有截斷，所以只測 XXL)

    @MainActor
    func testForecastChartAxisLabelsAreNotTruncatedAtXXL() throws {
        try assertForecastAxis(contentSize: Self.xxl)
    }

    @MainActor
    private func assertForecastAxis(contentSize: String) throws {
        let app = launchSignedIn(contentSize: contentSize)
        app.openHomeEntry("forecast")
        let chartTitle = app.staticTexts["未來 60 天逐日餘額"]
        // 大字級時預測圖在摘要下面，清單還沒捲到就不在畫面上。
        for _ in 0..<10 where !chartTitle.exists { app.swipeUp() }
        XCTAssertTrue(chartTitle.exists, "沒有看到預測圖")
        XCTAssertTrue(ScrollSupport.revealFully(chartTitle, in: app, inSheet: true), "預測圖標題捲不進畫面")
        ScrollSupport.nudge(app, by: 200)
        let lines = try TextRecognition.lines(in: app.screenshot().image)
        XCTAssertFalse(lines.contains { Self.isTruncated($0) }, "預測圖的刻度或文字被截斷:\(lines)")
    }

    // MARK: 預算額度編輯:金額列的標籤

    @MainActor
    func testBudgetEditorLabelIsNotTruncatedAtXXL() throws {
        let app = launchSignedIn(contentSize: Self.xxl)
        app.tabBars.buttons["統計"].tap()
        let add = app.buttons["budgets.add"]
        XCTAssertTrue(ScrollSupport.revealFully(add, in: app), "統計頁沒有找到新增預算額度")
        add.tap()
        XCTAssertTrue(app.textFields["budgetEditor.amount"].waitForExistence(timeout: 5), "沒有打開預算額度編輯")
        let lines = try TextRecognition.lines(in: app.screenshot().image)
        XCTAssertFalse(lines.contains { Self.isTruncated($0) }, "預算額度編輯的字被截斷:\(lines)")
        // 月份放區塊標題、標籤只有「預算」;標籤寫成「2026年10月的預算」大字級會被截斷(OCR 不一定認得出「…」)。
        XCTAssertFalse(lines.contains { $0.contains("月的") }, "金額列的標籤太長:\(lines)")
    }

    // MARK: 共用

    /// 被截斷的字:有「…」,或日期刻度只剩一半(「10月1」後面沒有「日」);OCR 常把「…」漏掉，所以也看日期。
    private static func isTruncated(_ line: String) -> Bool {
        line.contains("…") || line.contains("...") || line.contains(/\d{1,2}月\d{1,2}(?![\d日])/)
    }

    // MARK: 記帳頁的列:最長的內容組合在任何字級都不比螢幕寬(#246)

    /// 公帳三態、帳單狀態、長帳戶名稱、長記帳人、沒有備註的長標題系統紀錄(`-uiTestingLongRows`);
    /// `-uiTestingRowParts` 讓列的圖示、標題、次要文字、金額、帳戶各自可查詢，逐一確認都落在螢幕裡、金額沒有被裁掉。
    @MainActor
    func testTransactionRowPartsStayInsideTheScreenAtEverySize() throws {
        for (size, name) in [(nil, "預設字級"), ("UICTContentSizeCategoryXXL", "XXL"), (Self.ax5, "AX5")] as [(String?, String)] {
            let app = XCUIApplication.launchUITesting(
                flags: ["-uiTestingLongRows", "-uiTestingRowParts"], contentSize: size, signedIn: true
            )
            app.tabBars.buttons["記帳"].tap()
            let window = app.windows.firstMatch.frame
            var checked = 0
            for pass in 0..<4 {
                let parts = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "row.")).allElementsBoundByIndex
                for part in parts where part.exists && !part.frame.isEmpty {
                    // 捲出畫面上下的列不在這次檢查內;左右一律要在螢幕裡。
                    guard part.frame.maxY > window.minY, part.frame.minY < window.maxY else { continue }
                    checked += 1
                    XCTAssertGreaterThanOrEqual(part.frame.minX, window.minX - 1, "\(name):「\(part.identifier)」左邊被裁掉:\(part.frame)")
                    XCTAssertLessThanOrEqual(part.frame.maxX, window.maxX + 1, "\(name):「\(part.identifier)」右邊被裁掉:\(part.frame)")
                }
                if pass < 3 { app.swipeUp() }
            }
            XCTAssertGreaterThan(checked, 8, "\(name):沒有量到足夠的列內元素(\(checked)),測試資料或掛鉤沒有生效")
            app.terminate()
        }
    }

    @MainActor
    private func launchSignedIn(contentSize: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingOverdraftForecast", "-resetSession"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        app.signInWithSampleAccount()
        return app
    }
}
