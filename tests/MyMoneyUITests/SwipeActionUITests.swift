import XCTest

/// 滑動刪除的格式(#204):破壞性的滑動動作(刪除、移除)在深淺色模式都是紅底、有圖示,
/// 不是一顆空白的白色圓圈(深色模式的強調色是白色,沒指定紅色時 destructive 的紅會被蓋掉)。
final class SwipeActionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(dark: Bool, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"] + extra + (dark ? ["-AppleInterfaceStyle", "Dark"] : [])
        app.launch()
        app.signInWithSampleAccount()
        return app
    }

    /// 往左滑 `row`,量露出的動作鈕(標籤 `actionLabel`)有紅色底。
    @MainActor
    private func assertSwipeActionIsRed(_ row: XCUIElement, actionLabel: String, in app: XCUIApplication, _ name: String) throws {
        XCTAssertTrue(ScrollSupport.revealFully(row, in: app), "\(name):找不到要滑的列")
        row.swipeLeft()
        let action = app.buttons[actionLabel].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), "\(name):滑動後沒有「\(actionLabel)」")
        Thread.sleep(forTimeInterval: 0.6)
        let image = app.screenshot().image
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // 動作鈕的位置在螢幕右側:量鈕的範圍(含圓形底),要有紅色底。
        let window = app.windows.firstMatch.frame
        let region = CGRect(
            x: max(action.frame.minX - 24, 0) / window.width, y: max(action.frame.minY - 24, 0) / window.height,
            width: min(action.frame.width + 48, window.width - action.frame.minX + 24) / window.width,
            height: (action.frame.height + 48) / window.height
        )
        let ink = try PixelAnalysis.statistics(of: image, region: region)
        XCTAssertGreaterThan(ink.red, 200, "\(name):「\(actionLabel)」不是紅色底(紅色像素 \(ink.red)),可能是白色圓圈")
    }

    @MainActor
    func testTransactionDeleteIsRed() throws {
        for dark in [false, true] {
            let app = launch(dark: dark)
            app.tabBars.buttons["記帳"].tap()
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "午餐")).firstMatch
            try assertSwipeActionIsRed(row, actionLabel: "刪除", in: app, "記帳列 \(dark ? "深色" : "淺色")")
            app.terminate()
        }
    }

    @MainActor
    func testAccountCardDeleteIsRed() throws {
        for dark in [false, true] {
            let app = launch(dark: dark)
            app.tabBars.buttons["帳戶"].tap()
            let card = app.buttons["accounts.card.sample-card"]
            try assertSwipeActionIsRed(card, actionLabel: "刪除", in: app, "信用卡 \(dark ? "深色" : "淺色")")
            app.terminate()
        }
    }

    @MainActor
    func testRecurringDeleteIsRed() throws {
        for dark in [false, true] {
            let app = launch(dark: dark)
            app.openHomeEntry("recurring")
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "房租")).firstMatch
            try assertSwipeActionIsRed(row, actionLabel: "刪除", in: app, "週期收支 \(dark ? "深色" : "淺色")")
            app.terminate()
        }
    }

    @MainActor
    func testGoalDeleteIsRed() throws {
        for dark in [false, true] {
            let app = launch(dark: dark)
            app.openHomeEntry("goals")
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "沖繩旅遊")).firstMatch
            try assertSwipeActionIsRed(row, actionLabel: "刪除", in: app, "儲蓄目標 \(dark ? "深色" : "淺色")")
            app.terminate()
        }
    }

    @MainActor
    func testMemberRemoveIsRed() throws {
        for dark in [false, true] {
            let app = launch(dark: dark, extra: ["-uiTestingJoinedHousehold"])
            app.tabBars.buttons["家庭"].tap()
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "一般成員")).firstMatch
            try assertSwipeActionIsRed(row, actionLabel: "移除", in: app, "家庭成員 \(dark ? "深色" : "淺色")")
            app.terminate()
        }
    }
}
