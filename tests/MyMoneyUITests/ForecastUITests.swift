import XCTest

/// 規劃 → 現金流預測。資料來自 MyMoneyTestSupport 的 `InMemoryForecastRepository.sampleForToday()`(不連網路)。
final class ForecastUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 透支風險與最低餘額;購買力試算的三種評估結果。
    @MainActor
    func testRiskAndPurchaseCheck() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.openHomeEntry("forecast")
        XCTAssertTrue(element(in: app, labelContaining: "現金流充裕安全").waitForExistence(timeout: 5), "沒有看到透支風險")
        XCTAssertTrue(element(in: app, labelContaining: "最低餘額 53,440 元").exists, "沒有看到最低餘額")

        let amount = app.textFields["forecast.purchaseAmount"]
        for _ in 0..<5 where !amount.isHittable { app.swipeUp() }
        amount.tap()
        amount.typeText("60000")
        app.buttons["forecast.check"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "不建議購買").waitForExistence(timeout: 5), "沒有顯示評估結果")
    }

    /// 起始餘額(上游 5b2faa6、#195):預測頁多一組「起始餘額」,念出金額與現金、活存帳戶各是多少。
    @MainActor
    func testStartingBalanceShowsCashAndBankTotals() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.openHomeEntry("forecast")
        let start = app.descendants(matching: .any)["forecast.startingBalance"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "預測頁沒有起始餘額")
        XCTAssertEqual(start.label, "起始餘額")
        XCTAssertEqual(start.value as? String, "65,440 元,現金 $1,500・活存帳戶 $63,940")
    }

    /// 視角(上游 ADR 0016、#153):預測頁切到家庭公帳,最低餘額與預定收支換成公帳的;購買力試算跟著視角,切換時結論清掉。
    @MainActor
    func testScopeFilterChangesTheForecastAndClearsThePurchaseCheck() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.openHomeEntry("forecast")
        XCTAssertTrue(element(in: app, labelContaining: "最低餘額 53,440 元").waitForExistence(timeout: 5))

        let amount = app.textFields["forecast.purchaseAmount"]
        for _ in 0..<5 where !amount.isHittable { app.swipeUp() }
        amount.tap()
        amount.typeText("1000")
        app.buttons["forecast.check"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "放心購買").waitForExistence(timeout: 5))

        for _ in 0..<5 where !app.buttons["forecast.scope"].isHittable { app.swipeDown() }
        let filter = app.buttons["forecast.scope"]
        XCTAssertEqual(filter.value as? String, "全部")
        filter.tap()
        app.buttons["家庭公帳"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "最低餘額 18,000 元").waitForExistence(timeout: 5), "切到家庭公帳之後最低餘額沒有換成公帳的")
        XCTAssertEqual(filter.value as? String, "家庭公帳")
        XCTAssertFalse(element(in: app, labelContaining: "放心購買").exists, "換了視角,上一個視角的試算結論還在")
    }

    /// 預測事件可勾選「已繳」(上游 ADR 0018、#182):勾了之後最低餘額由後端重算(房租 12,000 不再計入)，
    /// 事件變淡並念出已繳;再點一次取消。
    @MainActor
    func testSettlingAnEventRecalculatesTheMinimumBalanceAndCanBeUndone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.openHomeEntry("forecast")
        XCTAssertTrue(element(in: app, labelContaining: "最低餘額 53,440 元").waitForExistence(timeout: 5))

        let settle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "forecast.settle.sample:rent")).firstMatch
        for _ in 0..<8 where !(settle.exists && settle.isHittable) { app.swipeUp() }
        XCTAssertTrue(settle.exists, "房租事件沒有勾選圓圈")
        XCTAssertEqual(settle.label, "標示為已繳")
        XCTAssertGreaterThanOrEqual(settle.frame.width, 44, "勾選圓圈寬度不到 44pt")
        XCTAssertGreaterThanOrEqual(settle.frame.height, 44, "勾選圓圈高度不到 44pt")
        settle.tap()

        let paid = element(in: app, labelContaining: "房租,")
        XCTAssertTrue(NSPredicate(format: "label CONTAINS %@", "已繳，不計入預測").evaluate(with: paid) || element(in: app, labelContaining: "已繳，不計入預測").waitForExistence(timeout: 5), "已繳的事件沒有念出已繳")
        XCTAssertEqual(settle.label, "取消已繳", "勾了之後圓圈的標籤沒有變")
        for _ in 0..<8 where !element(in: app, labelContaining: "最低餘額 65,440 元").exists { app.swipeDown() }
        XCTAssertTrue(element(in: app, labelContaining: "最低餘額 65,440 元").waitForExistence(timeout: 5), "已繳的房租還計入最低餘額")

        for _ in 0..<8 where !(settle.exists && settle.isHittable) { app.swipeUp() }
        settle.tap()
        XCTAssertEqual(settle.label, "標示為已繳", "取消後圓圈的標籤沒有恢復")
        for _ in 0..<8 where !element(in: app, labelContaining: "最低餘額 53,440 元").exists { app.swipeDown() }
        XCTAssertTrue(element(in: app, labelContaining: "最低餘額 53,440 元").waitForExistence(timeout: 5), "取消已繳後最低餘額沒有恢復")
    }

    /// 總覽的走勢線每個視角都有(以前只有「全部」)。
    @MainActor
    func testOverviewTrendIsShownInEveryScope() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let chart = element(in: app, labelContaining: "未來 30 天預測餘額")
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "全部視角沒有走勢線")
        let filter = app.buttons["overview.scope"]
        for scope in ["家庭公帳", "個人私帳"] {
            filter.tap()
            app.buttons[scope].tap()
            XCTAssertEqual(filter.value as? String, scope)
            XCTAssertTrue(element(in: app, labelContaining: "未來 30 天預測餘額").waitForExistence(timeout: 5), "\(scope)視角沒有走勢線")
        }
        XCTAssertTrue(element(in: app, labelContaining: "最低餘額 35,440 元").exists, "個人私帳視角的走勢線不是該視角的預測")
    }

    /// 預定收支列(#155):左邊名稱與「日期・歸屬」，右邊金額與資產帳戶，兩行右緣對齊;VoiceOver 念出歸屬與帳戶。
    @MainActor
    func testEventRowShowsOwnershipAndAccount() throws {
        let app = launch()
        let rent = element(in: app, labelContaining: "房租,")
        for _ in 0..<8 where !rent.exists { app.swipeUp() }
        XCTAssertTrue(rent.exists, "沒有預定收支「房租」")
        XCTAssertTrue(rent.label.contains("家庭公帳,帳戶 iOS 測試存款"), "VoiceOver 沒念歸屬與帳戶:\(rent.label)")
        XCTAssertTrue(ScrollSupport.revealFully(rent, in: app), "捲不到整列看得到")
        let image = rent.screenshot().image
        let text = try TextRecognition.lines(in: image).joined(separator: " ")
        XCTAssertTrue(text.contains("家庭公帳") && text.contains("測試存款"), "列上沒有歸屬與資產帳戶:\(text)")
        let bands = try PixelAnalysis.inkBands(of: image)
        XCTAssertEqual(bands.count, 2, "預定收支列應該是兩行:\(bands)")
        if bands.count == 2 {
            XCTAssertEqual(bands[0].maxX, bands[1].maxX, accuracy: 3 * Int(image.scale), "金額與資產帳戶右緣沒有對齊:\(bands)")
        }
    }

    /// 無障礙字級:名稱、日期・歸屬、資產帳戶由上往下，金額在最下面一行靠右，沒有字被截斷。
    @MainActor
    func testEventRowStacksWithAmountOnTheBottomRightAtAX5() throws {
        let app = launch(category: "UICTContentSizeCategoryAccessibilityXXXL")
        let rent = element(in: app, labelContaining: "房租,")
        for _ in 0..<12 where !rent.exists { app.swipeUp() }
        XCTAssertTrue(ScrollSupport.revealFully(rent, in: app), "捲不到整列看得到")
        let image = rent.screenshot().image
        let bands = try PixelAnalysis.inkBands(of: image)
        XCTAssertGreaterThanOrEqual(bands.count, 4, "AX5 應該是名稱、日期・歸屬、資產帳戶、金額由上往下:\(bands)")
        let amount = try XCTUnwrap(bands.last)
        let width = Int(image.size.width * image.scale)
        let gap = width - amount.maxX
        // 文字區塊右邊是 44pt 的「已繳」圓圈(#182):金額靠這個區塊的右緣，不會超出去。
        XCTAssertTrue(gap >= 0 && gap <= 40 * Int(image.scale), "金額沒有靠右:右邊空 \(gap) 畫素")
        // 金額在最下面一行、右緣貼著文字區塊的右緣(上面已量);文字區塊本身變窄了(右邊有已繳圓圈)，所以不再要求左緣離左邊多遠。
        XCTAssertGreaterThan(amount.minX, bands[0].minX - 1, "金額比名稱還靠左:\(amount) \(bands[0])")
        let recognized = try TextRecognition.lines(in: image).joined(separator: " ")
        XCTAssertFalse(recognized.contains("…") || recognized.contains("..."), "無障礙字級有字被截斷:\(recognized)")
    }

    @MainActor
    private func launch(category: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"] + (category.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        app.launch()
        signIn(app)
        // 大字級時列表長，入口會在畫面下方:`openHomeEntry` 會捲到看得到再點。
        app.openHomeEntry("forecast")
        return app
    }

    @MainActor
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "登入後沒有進入 tab 外殼")
    }
}
