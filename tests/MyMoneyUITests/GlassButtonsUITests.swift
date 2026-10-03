import XCTest

/// 單色玻璃按鈕(#134、ADR-0007):淺色黑字白底、深色白字黑底;可點的東西靠 Liquid Glass 外框，不靠顏色。
/// 沒有裸文字按鈕;sheet 的取消與確認是 ✕ 與 ✓;需要文字的主要動作是單色填滿的玻璃膠囊;選取狀態單色化。
final class GlassButtonsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
    }

    @MainActor
    func testSheetToolbarAndSelectionAreMonochromeInLight() throws {
        try assertSheetToolbarAndSelection(appearance: .light)
    }

    @MainActor
    func testSheetToolbarAndSelectionAreMonochromeInDark() throws {
        try assertSheetToolbarAndSelection(appearance: .dark)
    }

    /// 記一筆 sheet:✕ 玻璃圓鈕(VoiceOver 念「關閉」)與 ✓ 單色填滿圓鈕(念「儲存」)，觸控範圍至少 44×44pt;
    /// 預設選取的分類格是單色填滿(淺色黑底、深色白底)。
    @MainActor
    private func assertSheetToolbarAndSelection(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = launchSignedIn()
        let name = appearance == .dark ? "深色" : "淺色"

        app.buttons["overview.add"].tap()
        let close = app.buttons["關閉"]
        let save = app.buttons["quickEntry.save"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), "\(name):沒有「關閉」(✕)")
        XCTAssertTrue(save.exists, "\(name):沒有確認(✓)")
        XCTAssertEqual(save.label, "儲存", "\(name):✓ 的 VoiceOver 標籤不是「儲存」")
        // 工具列的 ✕ 與 ✓ 是系統的玻璃圓鈕(視覺 36pt):系統的觸控範圍把圓鈕外擴到 44pt，這裡在圓鈕外 4pt 點一下也要點得到。
        for (button, label) in [(close, "關閉"), (save, "儲存")] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 36, "\(name):「\(label)」太小:\(button.frame)")
            XCTAssertGreaterThanOrEqual(button.frame.height, 36, "\(name):「\(label)」太小:\(button.frame)")
        }
        XCTAssertFalse(app.navigationBars.buttons["取消"].exists, "\(name):sheet 還有文字的「取消」")

        try assertFilled(save, appearance: appearance, "\(name):✓ 不是單色填滿")

        // 預設選取的分類格(餐飲)是單色填滿:在表單最下面，要捲下去。
        // 金額欄一打開就對焦，鍵盤蓋住分類格:先收起。
        let done = app.keyboards.firstMatch.exists ? app.buttons["完成"].firstMatch : nil
        done?.tap()
        let category = app.buttons["餐飲"]
        for _ in 0..<8 where !(category.exists && category.isHittable) { app.swipeUp() }
        XCTAssertTrue(category.exists, "\(name):沒有找到分類格")
        XCTAssertTrue(category.isSelected, "\(name):餐飲不是選取狀態")
        try assertFilled(category, appearance: appearance, "\(name):選取的分類格不是單色填滿", minimum: 0.5)
        let other = app.buttons["交通"]
        if other.exists, other.isHittable {
            let unselected = try PixelAnalysis.statistics(of: other.screenshot().image)
            XCTAssertLessThan(
                appearance == .dark ? unselected.lightFraction : unselected.darkFraction, 0.3, "\(name):沒選的分類格也是填滿的"
            )
        }

        // 在 ✕ 左邊緣外 4pt 點一下(44pt 的觸控範圍):要關得掉 sheet。
        let outsideEdge = CGVector(dx: -4 / close.frame.width, dy: 0.5)
        close.coordinate(withNormalizedOffset: outsideEdge).tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 3), "\(name):按「關閉」(圓鈕外 4pt)之後 sheet 沒有關閉，觸控範圍不到 44pt")
    }

    /// 區塊標題沒有「管理」「全部」這類裸文字按鈕，改成「…」玻璃圓鈕(視覺 32pt、點擊範圍至少 44pt)，點開選單。
    @MainActor
    func testSectionHeadersUseMoreMenusInsteadOfTextButtons() throws {
        let app = launchSignedIn()
        let accountsMore = app.buttons["overview.accounts.more"]
        for _ in 0..<5 where !(accountsMore.exists && accountsMore.isHittable) { app.swipeUp() }
        XCTAssertTrue(accountsMore.exists, "帳戶區塊標題沒有「…」")
        XCTAssertGreaterThanOrEqual(accountsMore.frame.width, 44, "「…」寬度不到 44pt:\(accountsMore.frame)")
        XCTAssertGreaterThanOrEqual(accountsMore.frame.height, 44, "「…」高度不到 44pt:\(accountsMore.frame)")
        XCTAssertEqual(accountsMore.label, "帳戶的更多動作")

        let recentMore = app.buttons["overview.recent.more"]
        for _ in 0..<8 where !(recentMore.exists && recentMore.isHittable) { app.swipeUp() }
        XCTAssertTrue(recentMore.exists, "最近區塊標題沒有「…」")
        XCTAssertFalse(app.buttons["管理"].exists, "還有裸文字按鈕「管理」")
        XCTAssertFalse(app.buttons["全部"].exists, "還有裸文字按鈕「全部」")

        recentMore.tap()
        XCTAssertTrue(app.buttons["查看全部交易"].waitForExistence(timeout: 3), "選單沒有「查看全部交易」")
        XCTAssertTrue(app.buttons["記一筆"].exists, "選單沒有「記一筆」")
        app.buttons["查看全部交易"].tap()
        XCTAssertTrue(app.buttons["transactions.add"].waitForExistence(timeout: 3), "「查看全部交易」沒有進入交易 tab")
    }

    @MainActor
    func testMoreMenusHaveNoFrameInLight() throws {
        try assertMoreMenusHaveNoFrame(appearance: .light)
    }

    @MainActor
    func testMoreMenusHaveNoFrameInDark() throws {
        try assertMoreMenusHaveNoFrame(appearance: .dark)
    }

    /// 區塊標題的「…」只剩符號、沒有外框(使用者要求，#137):元件外緣一圈跟背景一樣;有玻璃圓鈕時外緣一圈都有邊線或底色。
    /// 可點範圍仍至少 44×44pt，選單項目還在。
    @MainActor
    private func assertMoreMenusHaveNoFrame(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = launchSignedIn()
        let name = appearance == .dark ? "深色" : "淺色"
        for identifier in ["overview.accounts.more", "overview.recent.more"] {
            let more = app.buttons[identifier]
            for _ in 0..<8 where !(more.exists && more.isHittable) { app.swipeUp() }
            XCTAssertTrue(more.exists, "\(name):沒有 \(identifier)")
            XCTAssertGreaterThanOrEqual(more.frame.width, 44, "\(name):\(identifier) 寬度不到 44pt:\(more.frame)")
            XCTAssertGreaterThanOrEqual(more.frame.height, 44, "\(name):\(identifier) 高度不到 44pt:\(more.frame)")
            let image = more.screenshot().image
            let ring = try PixelAnalysis.ringFrameFraction(of: image)
            XCTAssertLessThan(ring, 0.1, "\(name):\(identifier) 還有外框(外緣一圈有 \(ring) 跟背景不同)")
            // 符號本身(三個點)還在:元件中央有跟背景不同的像素。
            let symbol = try PixelAnalysis.statistics(of: image, region: PixelAnalysis.center)
            XCTAssertGreaterThan(symbol.darkFraction + symbol.lightFraction, 0.005, "\(name):\(identifier) 連符號都看不到")
        }
        let recentMore = app.buttons["overview.recent.more"]
        recentMore.tap()
        XCTAssertTrue(app.buttons["查看全部交易"].waitForExistence(timeout: 3), "\(name):選單沒有「查看全部交易」")
        XCTAssertTrue(app.buttons["記一筆"].exists, "\(name):選單沒有「記一筆」")
    }

    @MainActor
    func testTransferCapsuleIsFilledMonochromeInLight() throws {
        try assertTransferCapsule(appearance: .light)
    }

    @MainActor
    func testTransferCapsuleIsFilledMonochromeInDark() throws {
        try assertTransferCapsule(appearance: .dark)
    }

    /// 需要文字的主要動作(帳戶頁的「ATM 提款／轉帳」)是單色填滿的玻璃膠囊，不再用粉紅底配特例字色。
    @MainActor
    private func assertTransferCapsule(appearance: XCUIDevice.Appearance) throws {
        XCUIDevice.shared.appearance = appearance
        let app = launchSignedIn()
        app.tabBars.buttons["帳戶"].tap()
        let transfer = app.buttons["accounts.transfer"]
        for _ in 0..<5 where !(transfer.exists && transfer.isHittable) { app.swipeUp() }
        XCTAssertTrue(transfer.exists, "沒有「ATM 提款／轉帳」膠囊")
        let name = appearance == .dark ? "深色" : "淺色"
        XCTAssertGreaterThanOrEqual(transfer.frame.height, 44, "\(name):膠囊高度不到 44pt:\(transfer.frame)")
        try assertFilled(transfer, appearance: appearance, "\(name):膠囊不是單色填滿", minimum: 0.55)
    }

    // MARK: 輔助

    /// 填滿的是黑(淺色)或白(深色)。切換外觀、動畫剛結束時截圖可能還是舊的樣子，最多重試幾次。
    @MainActor
    private func assertFilled(
        _ element: XCUIElement, appearance: XCUIDevice.Appearance, _ message: String, minimum: Double = 0.45
    ) throws {
        var fraction = 0.0
        var content = 0.0
        for _ in 0..<6 {
            let stats = try PixelAnalysis.statistics(of: element.screenshot().image, region: PixelAnalysis.center)
            fraction = appearance == .dark ? stats.lightFraction : stats.darkFraction
            // 字與圖示是反色(淺色白字、深色黑字):底色填滿但字沒有反色(白底白字)時，反色的像素幾乎是 0。
            content = appearance == .dark ? stats.darkFraction : stats.lightFraction
            if fraction > minimum, content > 0.01 { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("\(message)(\(appearance == .dark ? "白" : "黑")色底占 \(fraction),反色的字或圖示占 \(content)，要有至少 0.01)")
    }

    @MainActor
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "登入後沒有進入 tab 外殼")
        return app
    }
}
