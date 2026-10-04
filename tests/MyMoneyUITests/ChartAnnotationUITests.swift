import UIKit
import XCTest

/// 記帳頁每日支出長條圖(#163、#157 逐頁 HIG 審查):最高那根的金額標註(「$1,000」)要畫在圖的範圍裡,
/// 跟上面「支出佔收入」的比例條至少隔 4pt。以前標註畫在圖的上緣外面,字級放大之後直接壓到比例條。
/// 圖與標註不是獨立的 accessibility 元素,所以用 OCR 量位置(同 `HouseholdHeroUITests`)。
final class ChartAnnotationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAnnotationStaysInsideTheChart() throws {
        try assertAnnotation(contentSize: nil)
    }

    @MainActor
    func testAnnotationStaysInsideTheChartAtXXL() throws {
        try assertAnnotation(contentSize: "UICTContentSizeCategoryXXL")
    }

    @MainActor
    func testAnnotationStaysInsideTheChartAtAccessibilitySize() throws {
        try assertAnnotation(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    @MainActor
    private func assertAnnotation(contentSize: String?) throws {
        // 每月 1 號只有一天,一根長條不是圖,不顯示。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        try XCTSkipIf(calendar.component(.day, from: .now) < 2, "每月 1 號沒有每日支出長條圖")

        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        app.signInWithSampleAccount()
        app.tabBars.buttons["記帳"].tap()

        let chart = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "本區間每日支出，最多的一天是")).firstMatch
        let ratio = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "支出佔收入百分之")).firstMatch
        XCTAssertTrue(ScrollSupport.revealFully(chart, in: app), "記帳頁沒有每日支出長條圖,或捲不到整張圖都看得到:\(chart.frame)")

        let screenHeight = app.windows.firstMatch.frame.height
        let observations = try TextRecognition.observations(in: app.screenshot().image)
        // 最高那根是今天(120 + 880 = 1,000);取離圖的上緣最近的「1,000」,避開主視覺的總支出。
        let amounts = observations.filter { $0.text.contains("1,000") }
        let annotation = try XCTUnwrap(
            amounts.min { distance($0, toTopOf: chart, screenHeight: screenHeight) < distance($1, toTopOf: chart, screenHeight: screenHeight) },
            "畫面上找不到長條圖的 $1,000 標註:\(observations.map(\.text))"
        )
        // box 的原點在左下:標註的上緣(點,由上往下量)。
        let annotationTop = (1 - annotation.box.maxY) * screenHeight
        // 比例條在圖的上面:標註跟它至少隔 4pt(以前標註畫在圖的上緣外面，字級放大之後直接壓到比例條)。
        XCTAssertTrue(ratio.exists && ratio.frame.maxY <= chart.frame.minY, "畫面上找不到圖上方的比例條:比例條 \(ratio.frame)、圖 \(chart.frame)")
        let gap = annotationTop - ratio.frame.maxY
        XCTAssertGreaterThanOrEqual(gap, 4, "標註跟比例條只隔 \(gap)pt(要至少 4pt):標註上緣 \(annotationTop)、比例條 \(ratio.frame)")
    }

    /// 標註中心到圖的上緣的距離(點)。
    private func distance(_ observation: TextRecognition.Observation, toTopOf chart: XCUIElement, screenHeight: CGFloat) -> CGFloat {
        abs((1 - observation.box.midY) * screenHeight - chart.frame.minY)
    }
}
