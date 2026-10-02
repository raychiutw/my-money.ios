import XCTest

/// 正式路徑(不帶 `-uiTesting`,也就是 TestFlight 版的 composition root)的互動色是**單色**(#134、ADR-0007):
/// 淺色黑字白底、深色白字黑底，主要按鈕是單色填滿的玻璃膠囊;不是品牌粉紅，也不是系統藍。品牌粉紅只留在 logo、App icon 與頭像。
///
/// 其他 UI 測試都帶 `-uiTesting`,走不到正式路徑。TestFlight 1.0 (36381212551) 的標題和按鈕都變成系統藍，
/// 原因是正式路徑的 `App.init()` 建立了 `EnvironmentValues()`(AccentColor 沒套到)。登入頁不會連網路，所以這裡直接啟動正式路徑。
final class BrandColorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
    }

    @MainActor
    func testLoginPageHasNoBlueAndNoBrandPinkInLight() throws {
        try assertLoginPage(appearance: .light)
    }

    @MainActor
    func testLoginPageHasNoBlueAndNoBrandPinkInDark() throws {
        try assertLoginPage(appearance: .dark)
    }

    /// 登入頁:標題與文字不是系統藍、不是品牌粉紅;「登入」是單色填滿(淺色黑底、深色白底);沒填資料時停用，看得出來。
    @MainActor
    private func assertLoginPage(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = XCUIApplication()
        app.launch()
        // 正式路徑沒有 -resetSession:模擬器裡如果手動登入過，會直接進 tab 外殼並連 prod,這時不跑。
        if app.tabBars.firstMatch.waitForExistence(timeout: 2) {
            throw XCTSkip("模擬器的正式 Keychain 裡有 session,登入頁看不到;請先登出或清除模擬器")
        }
        XCTAssertTrue(app.staticTexts["我的記帳本"].waitForExistence(timeout: 5), "沒有看到登入頁")
        let name = appearance == .dark ? "深色" : "淺色"

        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.exists, "沒有「登入」按鈕")
        XCTAssertFalse(submit.isEnabled, "\(name):還沒填資料，「登入」應該停用")
        let disabled = try PixelAnalysis.statistics(of: submit.screenshot().image)

        let email = app.textFields["login.email"]
        email.tap()
        email.typeText("someone@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        XCTAssertTrue(submit.isEnabled, "\(name):填了資料，「登入」應該啟用")

        let enabled = try PixelAnalysis.statistics(of: submit.screenshot().image, region: PixelAnalysis.center)
        if appearance == .dark {
            XCTAssertGreaterThan(enabled.lightFraction, 0.55, "深色:「登入」不是白底填滿(白色占 \(enabled.lightFraction))")
            XCTAssertGreaterThan(enabled.darkFraction, 0.01, "深色:「登入」的字不是黑色(白底白字，黑色只占 \(enabled.darkFraction))")
        } else {
            XCTAssertGreaterThan(enabled.darkFraction, 0.55, "淺色:「登入」不是黑底填滿(黑色占 \(enabled.darkFraction))")
            XCTAssertGreaterThan(enabled.lightFraction, 0.01, "淺色:「登入」的字不是白色(黑底黑字，白色只占 \(enabled.lightFraction))")
        }
        XCTAssertNotEqual(
            appearance == .dark ? disabled.lightFraction : disabled.darkFraction,
            appearance == .dark ? enabled.lightFraction : enabled.darkFraction,
            accuracy: 0.1, "\(name):停用與啟用的「登入」看不出差別"
        )

        let page = try PixelAnalysis.statistics(of: XCUIScreen.main.screenshot().image)
        XCTAssertEqual(page.bluish, 0, "\(name):登入頁有系統藍")
        XCTAssertEqual(page.brandPink, 0, "\(name):登入頁有品牌粉紅(互動色已經單色化，粉紅只留 logo、App icon 與頭像)")
    }
}
