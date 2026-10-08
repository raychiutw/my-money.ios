import XCTest

/// 金額的正負號與顏色(#202):錢出去、欠的是紅色,錢進來、正向的是綠色,存量為正與零是一般色。
/// 用截圖的像素判斷主要數字的顏色(系統紅與系統綠;品牌粉紅不算)。
final class SignColorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ appearance: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"] + (appearance.map { _ in ["-uiTestingDark"] } ?? [])
        app.launch()
        app.signInWithSampleAccount()
        return app
    }

    @MainActor
    private func ink(_ element: XCUIElement, in app: XCUIApplication, _ name: String) throws -> PixelAnalysis.Statistics {
        XCTAssertTrue(ScrollSupport.revealFully(element, in: app), "找不到「\(name)」")
        let image = element.screenshot().image
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // 只量上半部:磚的主要數字在標籤旁或下面,下面的組成明細是次要灰字。
        return try PixelAnalysis.statistics(of: image, region: CGRect(x: 0, y: 0, width: 1, height: 0.62))
    }

    /// 總覽三格磚:信用卡待繳是紅色負數、當月淨收支為正是綠色、可支配現金(存量)為正是一般色。
    @MainActor
    func testOverviewTilesSignsAndColors() throws {
        for appearance in [nil, "Dark"] as [String?] {
            let app = launch(appearance)
            let due = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "信用卡待繳")).firstMatch
            let dueInk = try ink(due, in: app, "信用卡待繳 \(appearance ?? "Light")")
            XCTAssertGreaterThan(dueInk.red, 30, "信用卡待繳不是紅色(紅 \(dueInk.red))")
            XCTAssertEqual(dueInk.green, 0, "信用卡待繳不該有綠色")

            let net = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "當月淨收支")).firstMatch
            let netInk = try ink(net, in: app, "當月淨收支 \(appearance ?? "Light")")
            XCTAssertGreaterThan(netInk.green, 30, "為正的當月淨收支不是綠色(綠 \(netInk.green))")
            XCTAssertEqual(netInk.red, 0, "為正的當月淨收支不該有紅色")

            let cash = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "真實可支配現金")).firstMatch
            let cashInk = try ink(cash, in: app, "可支配現金 \(appearance ?? "Light")")
            XCTAssertEqual(cashInk.green, 0, "存量為正不上綠")
            app.terminate()
        }
    }

    /// 週期收支:週期支出每月平均是紅色負數,週期收入是綠色正數。
    @MainActor
    func testRecurringSummarySignsAndColors() throws {
        let app = launch()
        app.openHomeEntry("recurring")
        let expense = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "週期支出每月平均")).firstMatch
        let expenseInk = try ink(expense, in: app, "週期支出每月平均")
        XCTAssertGreaterThan(expenseInk.red, 30, "週期支出每月平均不是紅色(紅 \(expenseInk.red))")
        let income = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "週期收入每月平均")).firstMatch
        let incomeInk = try ink(income, in: app, "週期收入每月平均")
        XCTAssertGreaterThan(incomeInk.green, 30, "週期收入每月平均不是綠色(綠 \(incomeInk.green))")
    }

    /// 帳戶頁:信用卡待繳是紅色負數,現金與活存帳戶餘額(存量)一般色。
    @MainActor
    func testAccountsSignsAndColors() throws {
        let app = launch()
        app.tabBars.buttons["帳戶"].tap()
        let due = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "信用卡待繳總額")).firstMatch
        let dueInk = try ink(due, in: app, "帳戶頁信用卡待繳")
        XCTAssertGreaterThan(dueInk.red, 30, "信用卡待繳總額不是紅色(紅 \(dueInk.red))")
        let cash = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "現金總額")).firstMatch
        let cashInk = try ink(cash, in: app, "帳戶頁現金")
        XCTAssertEqual(cashInk.green, 0, "現金(存量)為正不上綠")
    }
}
