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
        app.launchArguments = ["-uiTesting", "-resetSession"] + extra + (dark ? ["-uiTestingDark"] : [])
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

    /// 已報銷明細的「解除報銷」跟其他刪除一樣是紅色的滑動按鈕(以前是橘色的一般按鈕)。
    @MainActor
    func testSettledUnlinkIsRed() throws {
        for dark in [false, true] {
            let app = launch(dark: dark, extra: ["-uiTestingJoinedHousehold", "-uiTestingAdvanceStates"])
            app.tabBars.buttons["家庭"].tap()
            let reimburse = app.openMemberDetail("in-memory-member-1")
            XCTAssertTrue(reimburse.waitForExistence(timeout: 5), "沒有進到成員詳細頁")
            app.segmentedControls["advance.tab"].buttons["已結清明細"].tap()
            let row = app.descendants(matching: .any)["advance.settled.sample-settled-reimbursed"]
            try assertSwipeActionIsRed(row, actionLabel: "解除報銷", in: app, "解除報銷 \(dark ? "深色" : "淺色")")
            app.terminate()
        }
    }

    /// 全 app 列操作一致:長按沒有任何選單;列右側的 ⋯ 才是完整清單(交易:編輯、刪除)。
    @MainActor
    func testLongPressShowsNothingAndMoreMenuHasEditAndDelete() throws {
        let app = launch(dark: false)
        app.tabBars.buttons["記帳"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND identifier == ''", "午餐")).firstMatch
        XCTAssertTrue(ScrollSupport.revealFully(row, in: app), "找不到午餐這一列")
        let more = app.buttons.matching(NSPredicate(format: "label == %@", "午餐的更多動作")).firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 3), "交易列右側沒有 ⋯")
        XCTAssertTrue(ScrollSupport.revealFully(more, in: app), "⋯ 捲不到看得見")
        more.tap()
        for item in ["編輯", "刪除"] {
            XCTAssertTrue(app.buttons[item].firstMatch.waitForExistence(timeout: 3), "⋯ 選單沒有「\(item)」")
        }
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["刪除"].firstMatch.waitForNonExistence(timeout: 3), "點選單外面沒有收起 ⋯ 選單")

        // 長按只是按住的點擊(開編輯 sheet),不會出現選單。
        row.press(forDuration: 1.0)
        XCTAssertFalse(app.buttons["刪除"].waitForExistence(timeout: 1.5), "長按不該出現選單")
        XCTAssertFalse(app.buttons["刪除"].exists, "長按不該出現選單")

    }
}
