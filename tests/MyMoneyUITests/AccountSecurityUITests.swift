import XCTest

/// 「我的」 → 帳號安全(#338)。資料來自 MyMoneyTestSupport 的 `InMemoryAccountSecurityRepository.sample()`(不連網路):
/// 這支 iPhone 與一台「Chrome · macOS」。
final class AccountSecurityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 清單標出這台裝置;登出其他裝置先確認,之後只剩這台;修改密碼成功後提示其他裝置已登出。
    @MainActor
    func testSignOutOtherDevicesAndChangePassword() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)

        app.openMe()
        app.buttons["me.accountSecurity"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "Chrome · macOS").waitForExistence(timeout: 5), "沒有看到其他登入裝置")
        XCTAssertTrue(element(in: app, labelContaining: "這台裝置").exists, "沒有標出這台裝置")

        app.buttons["security.signOutOthers"].tap()
        let confirm = app.buttons["登出"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "登出其他所有裝置沒有先確認")
        confirm.tap()
        XCTAssertTrue(
            element(in: app, labelContaining: "Chrome · macOS").waitForNonExistence(timeout: 5), "登出其他裝置後清單還有那台"
        )
        XCTAssertFalse(app.buttons["security.signOutOthers"].isEnabled, "只剩這台時「登出其他所有裝置」應該停用")

        let current = app.secureTextFields["security.currentPassword"]
        XCTAssertTrue(ScrollSupport.revealFully(current, in: app, inSheet: true), "找不到目前密碼欄位")
        current.tap()
        current.typeText("old-secret")
        let new = app.secureTextFields["security.newPassword"]
        new.tap()
        new.typeText("12345")
        XCTAssertFalse(app.buttons["security.changePassword"].isEnabled, "新密碼不到 6 個字元不能送出")
        new.typeText("6")
        app.buttons["security.changePassword"].tap()
        // 提示在清單最底的 footer,收起鍵盤後可能在畫面外、還沒建立,先捲出來。
        let changed = app.staticTexts["security.passwordChanged"]
        XCTAssertTrue(ScrollSupport.revealFully(changed, in: app, inSheet: true), "修改密碼後沒有出現提示")
        XCTAssertTrue(changed.label.contains("其他裝置已登出"), "提示沒說其他裝置已登出:\(changed.label)")
    }

    @MainActor
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
