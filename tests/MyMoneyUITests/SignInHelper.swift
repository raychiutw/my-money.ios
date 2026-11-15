import XCTest

extension XCUIApplication {
    /// 登入範例帳號(`InMemoryAuthRepository.Member.sample`)。
    ///
    /// `-uiTesting` 的登入鈕不開系統登入視窗，直接以範例帳號登入(#334)。大字級時登入鈕可能在畫面外，先往上捲到點得到。
    @MainActor
    func signInWithSampleAccount() {
        let submit = buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "沒有看到登入頁")
        for _ in 0..<4 where !submit.isHittable { swipeUp() }
        submit.tap()
        // iPad 的 tab 在頂端或側邊(sidebarAdaptable),不一定在 `tabBars` 裡:用標籤或圖示的 identifier 找。
        let candidates = [tabBars.buttons["總覽"], buttons["house"].firstMatch, buttons["總覽"].firstMatch, cells["總覽"].firstMatch]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !candidates.contains(where: \.exists) { Thread.sleep(forTimeInterval: 0.25) }
        XCTAssertTrue(candidates.contains(where: \.exists), "登入後沒有進入 tab 外殼")
    }
}

extension XCUIApplication {
    /// 以 UI 測試的 in-memory 依賴啟動 app(#221):`-uiTesting` 一律帶;預設重設 session(`-resetSession`);
    /// `flags` 是 `-uiTestingJoinedHousehold` 這類情境旗標;`contentSize` 是系統字級類別;`signedIn` 時接著登入範例帳號。
    ///
    /// 不重設 session 時**不會**自動登入(relaunch 的測試依賴前一次啟動寫進 Keychain 的 session)。
    @MainActor
    static func launchUITesting(
        flags: [String] = [], contentSize: String? = nil, resettingSession: Bool = true, signedIn: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + flags + (resettingSession ? ["-resetSession"] : [])
            + (contentSize.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        app.launch()
        if signedIn { app.signInWithSampleAccount() }
        return app
    }
}
