import XCTest

/// 正式路徑(不帶 `-uiTesting`,也就是 TestFlight 版的 composition root)的未登入流程(#356)。
///
/// 其他 UI 測試都帶 `-uiTesting`,走不到正式路徑。App 沒有自己的登入頁(#356):未登入就自動開系統登入視窗(要等 scene 進前景,#351),
/// 使用者關掉會再開。以前這裡驗證登入頁沒有系統藍(#134),登入頁拿掉後未登入畫面只剩背景，品牌色改由登入後的 UI 測試涵蓋。
final class BrandColorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignInSheetOpensAutomaticallyAndReopensAfterClosing() throws {
        let app = XCUIApplication()
        app.launch()
        // 正式路徑沒有 -resetSession:模擬器裡如果手動登入過，會直接進 tab 外殼並連 prod,這時不跑。
        if app.tabBars.firstMatch.waitForExistence(timeout: 2) {
            throw XCTSkip("模擬器的正式 Keychain 裡有 session,看不到未登入畫面;請先登出或清除模擬器")
        }

        let cancel = waitForSignInSheet(app, "冷啟動沒有自動打開系統登入視窗")
        cancel.tap()
        // 等關掉的動畫跑完:不會再開的話，這時視窗已經不在。
        Thread.sleep(forTimeInterval: 3)

        _ = waitForSignInSheet(app, "關掉登入視窗後沒有再開")
        XCTAssertFalse(app.buttons["login.retry"].exists, "關掉視窗不是錯誤，不該顯示「重試」")
    }

    /// 系統登入視窗的「取消」:可能在 app 自己,也可能在 SafariViewService。
    @MainActor
    private func waitForSignInSheet(_ app: XCUIApplication, _ message: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label IN %@", ["Cancel", "取消"])
        let candidates = [app, XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")]
            .map { $0.buttons.matching(predicate).firstMatch }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !candidates.contains(where: \.exists) { Thread.sleep(forTimeInterval: 0.25) }
        guard let button = candidates.first(where: \.exists) else {
            XCTFail("\(message):\n\(app.debugDescription)")
            return candidates[0]
        }
        return button
    }
}
