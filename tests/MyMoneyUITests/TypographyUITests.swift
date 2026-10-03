import UIKit
import XCTest

/// 字級照系統的文字樣式放大縮小(#156):分段控制的字、總覽的大數字都跟著系統字級走(最小到最大無障礙字級)，
/// 沒有封頂、沒有被縮小。用「每個字級各啟動一次」量墨跡高度，跟 `UIFontMetrics` 算出的預期比例比對。
final class TypographyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let categories: [(name: String, key: String, category: UIContentSizeCategory)] = [
        ("S", "UICTContentSizeCategoryS", .small),
        ("L", "UICTContentSizeCategoryL", .large),
        ("XXXL", "UICTContentSizeCategoryXXXL", .extraExtraExtraLarge),
    ]

    /// `UIFontMetrics` 在這個字級的縮放後大小。
    private func scaled(_ style: UIFont.TextStyle, base: CGFloat, at category: UIContentSizeCategory) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: base, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }

    /// 「我的」頂部的「設定｜規劃」分段控制(在內容區,不像導覽列的項目會被系統限制字級範圍):字高跟著 subheadline 的縮放比例變
    /// (S 小、XXXL 大)，不封頂；無障礙字級換成選單，字照系統大小、沒有裁切。
    @MainActor
    func testSegmentedControlTextScalesWithTheSystemTextSize() throws {
        var heights: [String: Int] = [:]
        for entry in categories {
            let app = launchMe(entry.key)
            let control = app.segmentedControls["me.page"]
            XCTAssertTrue(control.waitForExistence(timeout: 5), "\(entry.name):沒有分段控制")
            let image = control.screenshot().image
            let bands = try PixelAnalysis.inkBands(of: image, minimumDifference: 80)
            let text = try XCTUnwrap(bands.max { ($0.maxY - $0.minY) < ($1.maxY - $1.minY) }, "\(entry.name):分段控制看不到字")
            heights[entry.name] = text.maxY - text.minY
            app.terminate()
        }
        let small = try XCTUnwrap(heights["S"]), large = try XCTUnwrap(heights["L"]), xxxl = try XCTUnwrap(heights["XXXL"])
        XCTAssertLessThan(small, large, "S 的字沒有比預設小:\(heights)")
        XCTAssertLessThan(large, xxxl, "XXXL 的字沒有比預設大(封頂了?):\(heights)")
        let expectedRatio = scaled(.subheadline, base: 15, at: .extraExtraExtraLarge) / scaled(.subheadline, base: 15, at: .large)
        let actualRatio = Double(xxxl) / Double(large)
        XCTAssertEqual(actualRatio, Double(expectedRatio), accuracy: 0.2, "XXXL 與預設的字高比 \(actualRatio)，預期約 \(expectedRatio)")

        // 無障礙字級:分段控制換成選單，字照系統大小、沒有裁切。
        let app = launchMe("UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(app.buttons["me.page"].waitForExistence(timeout: 5), "無障礙字級沒有改成選單")
        XCTAssertFalse(app.segmentedControls["me.page"].exists, "無障礙字級還是分段控制(字會被裁掉)")
    }

    /// 總覽的大數字是 Large Title 文字樣式:字高隨字級單調放大，最大無障礙字級沒有被縮小。
    @MainActor
    func testBigNumberScalesWithTheSystemTextSize() throws {
        var heights: [String: Int] = [:]
        let all = categories + [("AX5", "UICTContentSizeCategoryAccessibilityXXXL", UIContentSizeCategory.accessibilityExtraExtraExtraLarge)]
        for entry in all {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-resetSession", "-UIPreferredContentSizeCategoryName", entry.key]
            app.launch()
            signIn(app)
            let hero = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "淨可用餘額")).firstMatch
            XCTAssertTrue(hero.waitForExistence(timeout: 5), "\(entry.name):沒有大數字")
            let image = hero.screenshot().image
            let bands = try PixelAnalysis.inkBands(of: image, minimumDifference: 80)
            let number = try XCTUnwrap(bands.max { ($0.maxY - $0.minY) < ($1.maxY - $1.minY) })
            heights[entry.name] = number.maxY - number.minY
            app.terminate()
        }
        let small = try XCTUnwrap(heights["S"]), large = try XCTUnwrap(heights["L"]), xxxl = try XCTUnwrap(heights["XXXL"])
        let ax5 = try XCTUnwrap(heights["AX5"])
        XCTAssertTrue(small < large && large < xxxl && xxxl < ax5, "大數字沒有隨字級單調放大:\(heights)")
        let expectedRatio = scaled(.largeTitle, base: 34, at: .accessibilityExtraExtraExtraLarge) / scaled(.largeTitle, base: 34, at: .large)
        XCTAssertEqual(Double(ax5) / Double(large), Double(expectedRatio), accuracy: 0.3, "AX5 與預設的字高比不對(被縮小了?):\(heights)，預期約 \(expectedRatio)")
    }

    // MARK: 輔助

    @MainActor
    private func launchMe(_ category: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession", "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        signIn(app)
        app.openMe()
        return app
    }

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "登入後沒有進入 tab 外殼")
    }
}
