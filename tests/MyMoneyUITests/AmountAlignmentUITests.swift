import XCTest

/// 金額一律靠右(#149):摘要磚、帳戶卡片、家庭頁成員的待報銷都把金額放在右邊;信用卡的「N 日繳」在金額左邊的小字;
/// 無障礙字級改上下堆疊時,金額在最下面一行、靠右。「大數字」主視覺維持靠左(不在這裡檢查)。
/// 用截圖的墨跡帶(`PixelAnalysis.inkBands`)量位置:金額最後一條墨跡的右緣離元素右緣的距離,應該就是卡片的內距。
final class AmountAlignmentUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private let defaultSize = "UICTContentSizeCategoryL"
    private let xxl = "UICTContentSizeCategoryXXL"
    private let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    // MARK: 摘要磚

    /// 預設字級三欄:標籤在上靠左、金額在下靠右。
    @MainActor
    func testTileAmountsAreRightAlignedInThreeColumns() throws {
        let app = launch(category: defaultSize)
        for (index, tile) in overviewTiles(in: app).enumerated() {
            XCTAssertTrue(ScrollSupport.revealFully(tile, in: app), "第 \(index + 1) 格捲不到整格看得到")
            let image = tile.screenshot().image
            let bands = try PixelAnalysis.inkBands(of: image)
            // 標籤一行、金額一行,下面是組成明細(#178,兩行,窄了會折行)。
            XCTAssertGreaterThanOrEqual(bands.count, 3, "三欄的磚應該是標籤、金額、組成明細由上往下:\(bands)")
            let amount = bands[1]
            try assertRightEdge(amount, in: image, "第 \(index + 1) 格的金額沒有靠右")
            XCTAssertGreaterThan(amount.minX, 14 * Int(image.scale), "第 \(index + 1) 格的金額貼到左邊:\(amount)")
            let label = bands[0]
            XCTAssertLessThan(label.minX, 20 * Int(image.scale), "標籤沒有靠左:\(label)")
            for detail in bands.dropFirst(2) {
                try assertRightEdge(detail, in: image, "第 \(index + 1) 格的組成明細沒有靠右")
            }
        }
    }

    /// XXL、AX5 單欄:XXL 標籤靠左、金額靠右同一行;AX5 同一行放不下,標籤在上、金額在下一行靠右;組成明細都在金額底下靠右(#178)。
    @MainActor
    func testTileAmountsAreRightAlignedInSingleColumn() throws {
        for (category, amountBand) in [(xxl, 0), (ax5, 1)] {
            let app = launch(category: category)
            for (index, tile) in overviewTiles(in: app).enumerated() {
                XCTAssertTrue(ScrollSupport.revealFully(tile, in: app), "\(category):第 \(index + 1) 格捲不到整格看得到")
                let image = tile.screenshot().image
                let bands = try PixelAnalysis.inkBands(of: image)
                XCTAssertGreaterThan(bands.count, amountBand + 1, "\(category):第 \(index + 1) 格的行數不對(金額底下要有組成明細):\(bands)")
                let amount = bands[amountBand]
                try assertRightEdge(amount, in: image, "\(category):第 \(index + 1) 格的金額沒有靠右")
                for detail in bands.dropFirst(amountBand + 1) {
                    try assertRightEdge(detail, in: image, "\(category):第 \(index + 1) 格的組成明細沒有靠右")
                }
            }
            app.terminate()
        }
    }

    // MARK: 帳戶卡片

    /// 總覽的信用卡:第二行左邊是小字「5 日繳」,右邊是金額,金額靠右;「N 日繳」不再跟在金額右邊。
    @MainActor
    func testOverviewCreditCardHasDueDayOnTheLeftAndAmountOnTheRight() throws {
        let app = launch(category: defaultSize)
        try assertCreditCard(app.buttons["overview.card.sample-card"], in: app, hasCaptionOnTheLeft: true)
    }

    /// 帳戶頁的信用卡:小字「個人私帳・5 日繳」在左,金額在右。
    @MainActor
    func testAccountsCreditCardHasCaptionOnTheLeftAndAmountOnTheRight() throws {
        let app = launch(category: defaultSize)
        app.tabBars.buttons["帳戶"].tap()
        try assertCreditCard(app.buttons["accounts.card.sample-card"], in: app, hasCaptionOnTheLeft: true)
    }

    /// 無障礙字級:卡片上下堆疊,金額在最下面一行、靠右。
    @MainActor
    func testCardAmountIsOnTheBottomRightAtAX5() throws {
        let app = launch(category: ax5)
        app.tabBars.buttons["帳戶"].tap()
        let card = app.buttons["accounts.card.sample-card"]
        for _ in 0..<10 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.exists, "沒有信用卡卡片")
        XCTAssertTrue(ScrollSupport.revealFully(card, in: app), "捲不到整張卡片都看得到:\(card.frame)")
        let image = card.screenshot().image
        let bands = try PixelAnalysis.inkBands(of: image)
        XCTAssertGreaterThanOrEqual(bands.count, 3, "AX5 應該是圖示加名稱、小字、金額由上往下:\(bands)")
        let amount = try XCTUnwrap(bands.last)
        try assertRightEdge(amount, in: image, "AX5 卡片的金額沒有在最下面一行靠右")
        XCTAssertEqual(amount.clusters(minGap: 30 * Int(image.scale)), 1, "最下面一行只該有金額:\(amount)")
    }

    // MARK: 家庭頁

    /// 家庭頁成員的待報銷(無障礙字級堆疊時):金額在最下面一行、靠右。
    @MainActor
    func testMemberPendingAmountIsOnTheBottomRightAtAX5() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-resetSession", "-UIPreferredContentSizeCategoryName", ax5]
        app.launch()
        signIn(app)
        app.tabBars.buttons["家庭"].tap()
        let member = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "有待請款代墊")).firstMatch
        for _ in 0..<10 where !member.exists { app.swipeUp() }
        XCTAssertTrue(member.exists, "沒有看到有待報銷的成員")
        XCTAssertTrue(ScrollSupport.revealFully(member, in: app), "捲不到整列都看得到:\(member.frame)")
        let image = member.screenshot().image
        let bands = try PixelAnalysis.inkBands(of: image, skippingLeadingCluster: false)
        let amount = try XCTUnwrap(bands.last)
        try assertRightEdge(amount, in: image, "成員的待報銷金額沒有在最下面一行靠右", maxGap: 40)
        XCTAssertGreaterThan(amount.minX, Int(image.size.width * image.scale) / 3, "待報銷金額貼在左邊:\(amount)")
    }

    // MARK: 輔助

    @MainActor
    private func assertCreditCard(_ card: XCUIElement, in app: XCUIApplication, hasCaptionOnTheLeft: Bool) throws {
        XCTAssertTrue(card.waitForExistence(timeout: 5), "沒有信用卡卡片")
        XCTAssertTrue(ScrollSupport.revealFully(card, in: app), "捲不到整張卡片都看得到:\(card.frame)")
        let image = card.screenshot().image
        let scale = Int(image.scale)
        let bands = try PixelAnalysis.inkBands(of: image)
        XCTAssertEqual(bands.count, 2, "卡片應該是圖示加名稱一行、小字加金額一行:\(bands)")
        let line = try XCTUnwrap(bands.last)
        try assertRightEdge(line, in: image, "卡片的金額沒有靠右")
        // 小字在左、金額在右:兩群墨跡,左邊那群貼近左內距。
        XCTAssertEqual(line.clusters(minGap: 14 * scale), 2, "第二行應該是左邊小字、右邊金額兩群:\(line)")
        XCTAssertLessThan(line.minX, 24 * scale, "小字沒有靠左:\(line)")
        // 小字(含「日繳」)在左、金額在右:用 OCR 看字的位置。以前「N 日繳」在金額右邊。
        let observations = try TextRecognition.observations(in: image)
        let caption = try XCTUnwrap(observations.first { $0.text.contains("日繳") }, "認不出小字「N 日繳」:\(observations.map(\.text))")
        let amount = try XCTUnwrap(observations.first { $0.text.contains("15,500") }, "認不出金額:\(observations.map(\.text))")
        XCTAssertLessThan(caption.box.midX, amount.box.midX, "「N 日繳」應該在金額左邊:小字 \(caption.box)、金額 \(amount.box)")
    }

    private func assertRightEdge(
        _ band: PixelAnalysis.InkBand, in image: UIImage, _ message: String, maxGap: Int = 20
    ) throws {
        let scale = Int(image.scale)
        let width = Int(image.size.width) * scale
        let gap = width - band.maxX
        XCTAssertTrue(gap >= 6 * scale && gap <= maxGap * scale, "\(message):右邊空 \(gap) 畫素(\(gap / scale)pt),應該約是內距 12pt")
    }

    @MainActor
    private func overviewTiles(in app: XCUIApplication) -> [XCUIElement] {
        let tiles = [("真實可支配現金", "21,500 元"), ("當月淨收支", "44,000 元"), ("信用卡待繳", "28,500 元")]
            .map { label, value in
                app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value BEGINSWITH %@", label, value)).firstMatch
            }
        XCTAssertTrue(tiles[0].waitForExistence(timeout: 5), "沒有看到數字磚")
        for _ in 0..<6 where !tiles.allSatisfy(\.exists) { app.swipeUp() }
        return tiles
    }

    @MainActor
    private func launch(category: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession", "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        signIn(app)
        return app
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
