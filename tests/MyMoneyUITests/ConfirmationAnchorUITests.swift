import XCTest

/// 確認訊息(#169):iOS 26 在 iPhone 上把 `confirmationDialog` 畫成泡泡,箭頭指向掛 modifier 的 view。
/// 以前掛在整個畫面上,家庭頁下方的「離開家庭」按下去,泡泡出現在畫面上方、箭頭指著不相關的列。
/// 現在掛在觸發它的按鈕上:確認鈕要落在觸發按鈕附近(垂直距離不超過畫面高度的 45%)。
final class ConfirmationAnchorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLeaveHouseholdBubbleIsNextToTheButton() throws {
        try assertLeaveBubbleIsNearTheButton(contentSize: nil)
    }

    @MainActor
    func testLeaveHouseholdBubbleIsNextToTheButtonAtXXL() throws {
        try assertLeaveBubbleIsNearTheButton(contentSize: "UICTContentSizeCategoryXXL")
    }

    @MainActor
    func testLeaveHouseholdBubbleIsNextToTheButtonAtAccessibilitySize() throws {
        try assertLeaveBubbleIsNearTheButton(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }

    @MainActor
    private func assertLeaveBubbleIsNearTheButton(contentSize: String?) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-resetSession"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        app.signInWithSampleAccount()
        app.tabBars.buttons["家庭"].tap()
        XCTAssertTrue(app.staticTexts["我們家"].waitForExistence(timeout: 15), "沒有看到已加入的家庭頁")

        let leave = app.buttons["household.leave"]
        XCTAssertTrue(ScrollSupport.revealFully(leave, in: app), "家庭頁沒有「離開家庭」")
        let triggerMidY = leave.frame.midY
        leave.tap()

        let confirm = app.buttons["離開"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "沒有跳出確認訊息")
        let distance = abs(confirm.frame.midY - triggerMidY)
        let limit = app.windows.firstMatch.frame.height * 0.45
        XCTAssertLessThanOrEqual(
            distance, limit,
            "確認訊息離觸發它的按鈕太遠(\(Int(distance))pt，上限 \(Int(limit))pt):按鈕 \(leave.frame)、確認鈕 \(confirm.frame)"
        )
        XCTAssertTrue(confirm.isHittable, "確認鈕被擠出畫面:\(confirm.frame)")
        // 泡泡式的確認訊息沒有「取消」鈕(點外面就關掉),所以不檢查它。
    }
}
