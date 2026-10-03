import XCTest

/// 輸入欄的字要照系統字級縮放(#157 逐頁 HIG 審查):機器人模擬對話的輸入欄曾用 `.roundedBorder`,
/// 最大的無障礙字級下欄位和字還是原本的大小,旁邊的訊息卻放大了好幾倍。
/// 欄位的高度會跟著字級長,所以比較兩種字級下的高度。
final class TextScalingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBotInputFieldGrowsWithTextSize() {
        let normal = botInputHeight(contentSize: nil)
        let large = botInputHeight(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertGreaterThan(large, normal * 1.5, "無障礙字級下機器人輸入欄沒有跟著放大(預設 \(normal)pt,最大字級 \(large)pt)")
    }

    @MainActor
    private func botInputHeight(contentSize: String?) -> CGFloat {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        app.launch()
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123\n")
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 10), "登入後沒有進入 tab 外殼")
        app.openMe()
        let bot = app.buttons["機器人記帳"]
        for _ in 0..<6 where !(bot.exists && bot.isHittable) { app.swipeUp() }
        bot.tap()
        let chat = app.buttons["模擬對話"]
        XCTAssertTrue(chat.waitForExistence(timeout: 5), "沒有看到模擬對話入口")
        chat.tap()
        let field = app.textFields["bot.draft"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "沒有看到輸入欄")
        let height = field.frame.height
        app.terminate()
        return height
    }
}
