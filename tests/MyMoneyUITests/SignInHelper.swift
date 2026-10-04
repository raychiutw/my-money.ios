import XCTest

extension XCUIApplication {
    /// 登入範例帳號(`InMemoryAuthRepository.Member.sample`)。
    ///
    /// 用「登入」鈕送出，不用鍵盤的 Return:Return 會被系統當成表單送出，偶爾彈出「要儲存密碼嗎？」蓋住整個畫面，
    /// 後面的截圖與查詢全部落空(#157 的大字級測試遇過)。大字級時登入鈕可能被鍵盤擋住，先往上捲到點得到。
    @MainActor
    func signInWithSampleAccount() {
        let email = textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        let submit = buttons["login.submit"]
        for _ in 0..<4 where !(submit.exists && submit.isHittable) { swipeUp() }
        submit.tap()
        // iPad 的 tab 在頂端或側邊(sidebarAdaptable),不一定在 `tabBars` 裡:用標籤或圖示的 identifier 找。
        let candidates = [tabBars.buttons["總覽"], buttons["house"].firstMatch, buttons["總覽"].firstMatch, cells["總覽"].firstMatch]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !candidates.contains(where: \.exists) { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(candidates.contains(where: \.exists), "登入後沒有進入 tab 外殼")
    }
}
