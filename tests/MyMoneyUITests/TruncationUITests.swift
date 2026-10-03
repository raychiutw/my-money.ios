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

    // MARK: 總覽的目標圓環:「100%」是環中最長的字

    @MainActor
    func testAchievedGoalRingShowsFullPercent() throws {
        try assertAchievedRing(contentSize: nil)
    }

    @MainActor
    func testAchievedGoalRingShowsFullPercentAtAccessibilitySize() throws {
        try assertAchievedRing(contentSize: Self.ax5)
    }

    @MainActor
    private func assertAchievedRing(contentSize: String?) throws {
        let app = launchSignedIn(contentSize: contentSize)
        // 範例資料的「iOS 小目標」已達成。
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "iOS 小目標，已達成百分之 100")).firstMatch
        XCTAssertTrue(ScrollSupport.revealFully(row, in: app), "總覽沒有找到已達成的目標圓環")

        // 環在列的最左邊，是一個正方形:只辨識這一塊，名稱不混進來。
        let cg = try XCTUnwrap(row.screenshot().image.cgImage)
        let side = min(cg.height, cg.width)
        let ringArea = try XCTUnwrap(cg.cropping(to: CGRect(x: 0, y: (cg.height - side) / 2, width: side, height: side)))
        let lines = try TextRecognition.lines(in: UIImage(cgImage: ringArea))
        XCTAssertTrue(lines.contains { $0.contains("100%") }, "圓環裡的百分比沒有完整顯示成「100%」,辨識到:\(lines)")
        XCTAssertFalse(lines.contains { Self.isTruncated($0) }, "圓環裡的字被截斷:\(lines)")
    }

    // MARK: 總覽「最近」的交易列:名稱不能被擠成一字一行

    @MainActor
    func testCompactTransactionTitleStaysReadableAtAccessibilitySize() throws {
        let app = launchSignedIn(contentSize: Self.ax5)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "耳機")).firstMatch
        XCTAssertTrue(ScrollSupport.revealFully(row, in: app), "總覽沒有找到「耳機」那筆最近交易")
        // 名稱被擠成一字一行時，OCR 會把「耳」「機」認成兩行。
        let lines = try TextRecognition.lines(in: row.screenshot().image)
        XCTAssertTrue(lines.contains { $0.contains("耳機") }, "最近交易的名稱被擠成一字一行:\(lines)")
    }

    // MARK: 現金流預測圖的日期刻度(無障礙字級系統自己會少放刻度，舊程式也沒有截斷，所以只測 XXL)

    @MainActor
    func testForecastChartAxisLabelsAreNotTruncatedAtXXL() throws {
        try assertForecastAxis(contentSize: Self.xxl)
    }

    @MainActor
    private func assertForecastAxis(contentSize: String) throws {
        let app = launchSignedIn(contentSize: contentSize)
        app.openMe()
        app.selectMePage("規劃")
        let forecast = app.buttons["現金流預測"]
        for _ in 0..<8 where !(forecast.exists && forecast.isHittable) { app.swipeUp() }
        forecast.tap()
        let chartTitle = app.staticTexts["未來 30 天逐日餘額"]
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

    @MainActor
    private func launchSignedIn(contentSize: String?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingOverdraftForecast", "-resetSession"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        // 密碼欄按 Return 就送出;大字級時登入按鈕可能被鍵盤擋住。
        password.typeText("secret123\n")
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 10), "登入後沒有進入 tab 外殼")
        return app
    }
}
