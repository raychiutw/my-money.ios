import XCTest

extension XCUIApplication {
    /// 登入範例帳號(`InMemoryAuthRepository.Member.sample`),等到進入 tab 外殼。
    ///
    /// App 沒有自己的登入頁(#356):未登入就自動開登入視窗,`-uiTesting` 不開系統視窗、直接以範例帳號登入(#334),
    /// 所以這裡只要等;主動登出後停在登入入口頁(#367)時先按「登入」。
    @MainActor
    func signInWithSampleAccount() {
        // iPad 的 tab 在頂端或側邊(sidebarAdaptable),不一定在 `tabBars` 裡:用標籤或圖示的 identifier 找。
        let candidates = [tabBars.buttons["總覽"], buttons["house"].firstMatch, buttons["總覽"].firstMatch, cells["總覽"].firstMatch]
        let entry = buttons["login.entry"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !candidates.contains(where: \.exists) {
            if entry.exists { entry.tap() }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(candidates.contains(where: \.exists), "登入後沒有進入 tab 外殼")
    }
}

extension XCUIApplication {
    /// 以 UI 測試的 in-memory 依賴啟動 app(#221):`-uiTesting` 一律帶;預設重設 session(`-resetSession`);
    /// `flags` 是 `-uiTestingJoinedHousehold` 這類情境旗標;`contentSize` 是系統字級類別;`signedIn` 時接著登入範例帳號。
    ///
    /// 沒有 session 時一律自動登入(#356);`signedIn` 只決定要不要等到進入 tab 外殼。
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
