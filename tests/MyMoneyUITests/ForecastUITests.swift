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

        app.openPlanning()
        app.buttons["現金流預測"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "現金流充裕安全").waitForExistence(timeout: 5), "沒有看到透支風險")
        XCTAssertTrue(element(in: app, labelContaining: "最低餘額 53,440 元").exists, "沒有看到最低餘額")

        let amount = app.textFields["forecast.purchaseAmount"]
        for _ in 0..<5 where !amount.isHittable { app.swipeUp() }
        amount.tap()
        amount.typeText("60000")
        app.buttons["forecast.check"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "不建議購買").waitForExistence(timeout: 5), "沒有顯示評估結果")
    }

    /// 視角(上游 ADR 0016、#153):預測頁切到家庭公帳,最低餘額與預定收支換成公帳的;購買力試算跟著視角,切換時結論清掉。
    @MainActor
    func testScopeFilterChangesTheForecastAndClearsThePurchaseCheck() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.openPlanning()
        app.buttons["現金流預測"].tap()
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
        XCTAssertTrue(gap >= 6 * Int(image.scale) && gap <= 40 * Int(image.scale), "金額沒有靠右:右邊空 \(gap) 畫素")
        XCTAssertGreaterThan(amount.minX, width / 3, "金額貼在左邊:\(amount)")
        let recognized = try TextRecognition.lines(in: image).joined(separator: " ")
        XCTAssertFalse(recognized.contains("…") || recognized.contains("..."), "無障礙字級有字被截斷:\(recognized)")
    }

    @MainActor
    private func launch(category: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"] + (category.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        app.launch()
        signIn(app)
        app.openPlanning()
        app.buttons["現金流預測"].tap()
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
