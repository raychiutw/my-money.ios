import XCTest

/// 正式路徑(不帶 `-uiTesting`,也就是 TestFlight 版的 composition root)的互動色是**單色**(#134、ADR-0007):
/// 淺色黑字、深色白字，主要按鈕是不填色的玻璃膠囊(#147、ADR-0008);不是系統藍。品牌粉紅用在 logo、App icon、頭像、
/// 目前所在的 tab、套用中的篩選與選取狀態，登入頁沒有這些，所以不該有粉紅。
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

    /// 登入頁:標題與文字不是系統藍、不是品牌粉紅;「登入」是不填色的玻璃膠囊;沒填資料時停用，看得出來。
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
        let disabled = try PixelAnalysis.statistics(of: submit.screenshot().image, region: PixelAnalysis.center)

        let email = app.textFields["login.email"]
        email.tap()
        email.typeText("someone@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        XCTAssertTrue(submit.isEnabled, "\(name):填了資料，「登入」應該啟用")

        let enabled = try PixelAnalysis.statistics(of: submit.screenshot().image, region: PixelAnalysis.center)
        // 不填色(#147):「登入」是玻璃膠囊，中央不是大面積的黑(淺色)或白(深色);粗體字看得到。
        let enabledFill = appearance == .dark ? enabled.lightFraction : enabled.darkFraction
        let disabledFill = appearance == .dark ? disabled.lightFraction : disabled.darkFraction
        XCTAssertLessThan(enabledFill, 0.3, "\(name):「登入」又被填成實心了(\(appearance == .dark ? "白" : "黑")色占 \(enabledFill))")
        XCTAssertGreaterThan(enabledFill, 0.003, "\(name):「登入」的字看不到(\(appearance == .dark ? "白" : "黑")色只占 \(enabledFill))")
        // 停用時字與外框變淡:主要文字色的像素比啟用時少。
        XCTAssertGreaterThan(enabledFill, disabledFill, "\(name):停用與啟用的「登入」看不出差別(啟用 \(enabledFill)、停用 \(disabledFill))")

        let page = try PixelAnalysis.statistics(of: XCUIScreen.main.screenshot().image)
        XCTAssertEqual(page.bluish, 0, "\(name):登入頁有系統藍")
        XCTAssertEqual(page.ci, 0, "\(name):登入頁有品牌粉紅(互動色已經單色化，粉紅只留 logo、App icon 與頭像)")
    }
}
