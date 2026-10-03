import UIKit
import XCTest

/// 家庭頁主視覺(#121、#157 逐頁 HIG 審查):「誰轉給誰」那行字跟下面長條圖最高那根的金額標註之間要有空隙。
/// 曾經標註緊貼著(大字級時直接壓在字上)。長條圖和那行字都不是獨立的 accessibility 元素，所以用 OCR 量位置。
final class HouseholdHeroUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSettlementLineDoesNotTouchChartAnnotation() throws {
        try assertGap(contentSize: nil)
    }

    @MainActor
    func testSettlementLineDoesNotTouchChartAnnotationAtXXL() throws {
        try assertGap(contentSize: "UICTContentSizeCategoryXXL")
    }

    @MainActor
    func testSettlementLineDoesNotTouchChartAnnotationAtAccessibilitySize() throws {
        try assertGap(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    @MainActor
    private func assertGap(contentSize: String?) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-resetSession"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123\n")
        XCTAssertTrue(app.tabBars.buttons["家庭"].waitForExistence(timeout: 10), "登入後沒有進入 tab 外殼")
        app.tabBars.buttons["家庭"].tap()
        XCTAssertTrue(app.buttons["household.leave"].waitForExistence(timeout: 5) || app.staticTexts["我們家"].waitForExistence(timeout: 5), "沒有看到已加入的家庭頁")

        let observations = try TextRecognition.observations(in: app.screenshot().image)
        // 字被標註蓋住時，OCR 會把兩者認成同一行(例如「$6,000給小明」)。
        XCTAssertFalse(
            observations.contains { $0.text.contains("6,000") && ($0.text.contains("給") || $0.text.contains("小明")) },
            "「誰轉給誰」那行字跟 $6,000 標註疊在一起:\(observations.map(\.text))"
        )
        // 那一行是「小美 轉給 小明」:OCR 常把「轉給」認成別的字，改用兩個成員的名字認(長條圖底下的刻度一次只有一個名字)。
        let line = try XCTUnwrap(
            observations.first { $0.text.contains("小美") && $0.text.contains("小明") },
            "畫面上找不到「誰轉給誰」那行字:\(observations.map(\.text))"
        )
        // 長條圖最高那根(小明代墊 6,000)的金額標註。
        let annotation = try XCTUnwrap(observations.first { $0.text.contains("6,000") }, "畫面上找不到長條圖的 $6,000 標註:\(observations.map(\.text))")
        // box 的原點在左下:標註在字的下面，標註的上緣(minY + height)要比字的下緣(minY)低，而且至少隔 4pt。
        let screenHeight = app.windows.firstMatch.frame.height
        let gap = (line.box.minY - annotation.box.maxY) * screenHeight
        XCTAssertGreaterThanOrEqual(gap, 4, "「誰轉給誰」那行字跟 $6,000 標註只隔 \(gap)pt(要至少 4pt):字 \(line.box)、標註 \(annotation.box)")
    }
}
