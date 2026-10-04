import UIKit
import XCTest

/// iPad 的內容寬度(#173、HIG Layout):登入、註冊與五個 tab 的內容限制在可讀寬度(約 700pt)並置中,
/// 不隨視窗拉伸(以前直向 820pt 寬的登入欄位有 800pt,清單的名稱和金額隔七百多 pt)。
/// 只在 iPad 模擬器跑(`-destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'`),iPhone 直接略過。
final class IPadLayoutUITests: XCTestCase {
    /// 內容最大寬度 700pt,加一點誤差(捲動條、陰影)。
    private let limit: CGFloat = 720

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "只在 iPad 驗證可讀寬度")
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testLoginContentIsLimitedInPortraitAndLandscape() throws {
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-resetSession"]
            app.launch()
            let submit = app.buttons["login.submit"]
            XCTAssertTrue(submit.waitForExistence(timeout: 10), "沒有登入頁")
            assertLimited(submit, in: app, "登入鈕(\(orientation.rawValue))")
            let email = app.textFields["login.email"]
            assertLimited(email, in: app, "登入的 email 欄位(\(orientation.rawValue))")
            app.terminate()
        }
    }

    @MainActor
    func testTabContentIsLimitedInPortrait() throws {
        try assertTabs(orientation: .portrait)
    }

    @MainActor
    func testTabContentIsLimitedInLandscape() throws {
        try assertTabs(orientation: .landscapeLeft)
    }

    @MainActor
    private func assertTabs(orientation: UIDeviceOrientation) throws {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        app.signInWithSampleAccount()

        // 總覽:功能入口兩欄合起來的寬度。
        let first = app.buttons["home.entry.ledger"], second = app.buttons["home.entry.accounts"]
        XCTAssertTrue(ScrollSupport.revealFully(first, in: app), "總覽沒有功能入口")
        let span = max(first.frame.maxX, second.frame.maxX) - min(first.frame.minX, second.frame.minX)
        XCTAssertLessThanOrEqual(span, limit, "總覽的功能入口撐滿寬度(\(span)pt):\(first.frame) \(second.frame)")
        assertCentered(CGRect(x: min(first.frame.minX, second.frame.minX), y: 0, width: span, height: 1), in: app, "總覽的功能入口")

        // 記帳:一筆收支明細的列。
        select(tab: "記帳", in: app)
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "午餐")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "記帳頁沒有收支明細")
        assertLimited(row, in: app, "記帳頁的收支明細列")

        // 帳戶:信用卡卡片。
        select(tab: "帳戶", in: app)
        let card = app.buttons["accounts.card.sample-card"]
        XCTAssertTrue(ScrollSupport.revealFully(card, in: app), "帳戶頁沒有信用卡")
        assertLimited(card, in: app, "帳戶頁的信用卡卡片")

        // 家庭:還沒加入家庭時是建立家庭的表單。
        select(tab: "家庭", in: app)
        let create = app.buttons["household.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "家庭頁沒有建立家庭的按鈕")
        assertLimited(create, in: app, "家庭頁的建立鈕")

        // 統計:新增預算額度。
        select(tab: "統計", in: app)
        let budgets = app.buttons["budgets.add"]
        XCTAssertTrue(ScrollSupport.revealFully(budgets, in: app), "統計頁沒有新增預算額度")
        assertLimited(budgets, in: app, "統計頁的新增預算額度")
    }

    /// iPad 的 tab 按鈕在 sidebar 或頂端的 tab bar:用標籤找。
    @MainActor
    private func select(tab: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[tab].exists ? app.tabBars.buttons[tab] : app.buttons[tab].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "找不到 tab「\(tab)」")
        button.tap()
    }

    @MainActor
    private func assertLimited(_ element: XCUIElement, in app: XCUIApplication, _ name: String) {
        XCTAssertLessThanOrEqual(element.frame.width, limit, "\(name)撐滿寬度(\(element.frame.width)pt，上限 \(limit)pt):\(element.frame)")
        assertCentered(element.frame, in: app, name)
    }

    @MainActor
    private func assertCentered(_ frame: CGRect, in app: XCUIApplication, _ name: String) {
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(frame.midX, window.midX, accuracy: 24, "\(name)沒有置中:\(frame)，視窗 \(window)")
    }
}
