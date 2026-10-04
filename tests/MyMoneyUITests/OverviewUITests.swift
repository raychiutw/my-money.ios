import XCTest

/// 「總覽」tab。資料來自 MyMoneyTestSupport 的範例資料(日期相對於今天，不連網路)。
final class OverviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 從總覽記一筆 250 元 → 當月淨收支和「記帳」入口的本月筆數跟著更新;點「記帳」入口進入記帳 tab。
    @MainActor
    func testQuickEntryUpdatesMonthNetAndLedgerCount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        // 範例：收入 45,000,支出 120 + 880(信用卡還款不算)。
        XCTAssertTrue(row("當月淨收支", value: "44,000 元", in: app).waitForExistence(timeout: 5), "沒有看到當月淨收支")
        let ledger = app.buttons["home.entry.ledger"]
        XCTAssertTrue(ScrollSupport.revealFully(ledger, in: app), "總覽沒有「記帳」入口")
        XCTAssertEqual(ledger.label, "記帳，本月 4 筆", "「記帳」入口沒有念出本月筆數")

        app.buttons["overview.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("250")
        app.chooseQuickEntryAccount()
        app.buttons["quickEntry.save"].tap()

        XCTAssertTrue(row("當月淨收支", value: "43,750 元", in: app).waitForExistence(timeout: 5), "記一筆後當月淨收支沒有更新")
        XCTAssertTrue(ScrollSupport.revealFully(ledger, in: app), "記一筆後找不到「記帳」入口")
        XCTAssertEqual(ledger.label, "記帳，本月 5 筆", "記一筆後「記帳」入口的本月筆數沒有更新")

        ledger.tap()
        XCTAssertTrue(app.buttons["transactions.add"].waitForExistence(timeout: 3), "「記帳」入口沒有進入記帳 tab")
    }

    /// 主視覺(#116):超大的淨可用餘額在最上面，下面是 30 天走勢圖，再下面是三格數字磚(#117):
    /// 真實可支配現金、當月淨收支、信用卡待繳;沒有公式明細。
    @MainActor
    func testHeroShowsBigBalanceAndForecastChartAboveSummaryTiles() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let available = row("淨可用餘額", value: "21,500 元", in: app)
        XCTAssertTrue(available.waitForExistence(timeout: 5), "沒有淨可用餘額")
        // 後端預測的 30 天走勢圖:念出最低餘額與會不會透支(範例預測不會透支)，位置在大數字下面、摘要列上面。
        let chart = element(in: app, labelContaining: "未來 30 天預測餘額，最低餘額")
        XCTAssertTrue(chart.exists, "沒有 30 天走勢圖")
        XCTAssertTrue(chart.label.hasSuffix("不會透支"), "走勢圖的摘要沒有說明會不會透支:\(chart.label)")
        XCTAssertLessThan(available.frame.minY, chart.frame.minY, "走勢圖不在淨可用餘額下面")
        // 大數字比一般金額列大很多。
        XCTAssertGreaterThan(available.frame.height, 50, "淨可用餘額不是大數字")
        XCTAssertFalse(element(in: app, labelContaining: "淨可用餘額 21,500").exists, "淨可用餘額不該同時有一般摘要列")
        for (label, value) in [("真實可支配現金", "21,500 元"), ("當月淨收支", "44,000 元"), ("信用卡待繳", "28,500 元")] {
            let summaryRow = row(label, value: value, in: app)
            XCTAssertTrue(summaryRow.exists, "摘要沒有「\(label) \(value)」這一磚")
            XCTAssertLessThan(chart.frame.maxY, summaryRow.frame.minY, "走勢圖不在「\(label)」上面")
        }
        // 淨可用餘額底下一行組成(#178),後端的值;三格數字磚各帶兩行組成明細。
        let composition = app.descendants(matching: .any)["overview.composition"]
        XCTAssertTrue(composition.exists, "淨可用餘額底下沒有組成一行")
        XCTAssertEqual(composition.label, "現金 0 元，加活存帳戶 50,000 元，減信用卡待繳 28,500 元", "組成一行的念法不對")
        XCTAssertLessThan(available.frame.minY, composition.frame.minY, "組成一行不在淨可用餘額下面")
        XCTAssertLessThan(composition.frame.maxY, chart.frame.minY, "組成一行不在走勢圖上面")
        let cardTile = row("信用卡待繳", value: "28,500 元", in: app)
        XCTAssertTrue((cardTile.value as? String ?? "").contains("2 張信用卡"), "信用卡待繳磚沒有張數:\(String(describing: cardTile.value))")
        let netTile = row("當月淨收支", value: "44,000 元", in: app)
        XCTAssertTrue((netTile.value as? String ?? "").contains("收入 45,000 元，支出 1,000 元"), "當月淨收支磚沒有收入與支出:\(String(describing: netTile.value))")
    }

    /// 功能入口格(#178):8 個入口都在,念成「名稱，關鍵數字」;點了切到對應的 tab 或 push 對應的畫面。
    @MainActor
    func testEntriesOpenTheirScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let expected = [
            ("ledger", "記帳，本月 4 筆"), ("accounts", "帳戶，3 個帳戶"), ("creditCards", "信用卡，待繳 28,500 元"),
            ("household", "家庭"), ("statistics", "統計，"), ("recurring", "週期收支，"), ("goals", "儲蓄目標，已存 4,000 元，整體達成率 2.5%"),
            ("forecast", "現金流預測，最低 53,440 元"),
        ]
        _ = app.descendants(matching: .any)["overview.composition"].waitForExistence(timeout: 10)
        for (id, label) in expected {
            let entry = app.buttons["home.entry.\(id)"]
            XCTAssertTrue(ScrollSupport.revealFully(entry, in: app), "總覽沒有「\(id)」入口")
            XCTAssertTrue(entry.label.hasPrefix(label), "「\(id)」入口的念法不對:\(entry.label)，預期以「\(label)」開頭")
        }

        // 切 tab 的入口:點了選到對應的 tab，再回總覽。
        for (id, tab) in [("ledger", "記帳"), ("accounts", "帳戶"), ("creditCards", "帳戶"), ("household", "家庭"), ("statistics", "統計")] {
            app.openHomeEntry(id)
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 3) && app.tabBars.buttons[tab].isSelected, "「\(id)」入口沒有切到「\(tab)」")
            app.tabBars.buttons["總覽"].tap()
        }

        // push 的入口:進得去,返回回到總覽。
        for (id, marker) in [("recurring", "recurring.add"), ("goals", "goals.add"), ("forecast", "forecast.scope")] {
            app.openHomeEntry(id)
            XCTAssertTrue(app.descendants(matching: .any)[marker].waitForExistence(timeout: 5), "「\(id)」入口沒有進到對應的畫面")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["overview.composition"].waitForExistence(timeout: 5), "「\(id)」返回之後沒有回到總覽")
        }
    }

    /// 接下來 30 天(#189):列出預定收支,右邊的圓圈標示「已繳」;已繳的變淡、念出「已繳,不計入預測」,
    /// 預測入口的最低餘額由後端重算,進預測頁看到同一筆也是已繳(兩邊同步)。
    @MainActor
    func testUpcomingEventsCanBeSettledFromHome() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        _ = app.descendants(matching: .any)["overview.composition"].waitForExistence(timeout: 10)
        let settle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "overview.settle.sample:rent")).firstMatch
        XCTAssertTrue(ScrollSupport.revealFully(settle, in: app), "總覽的「接下來 30 天」沒有房租的已繳圓圈")
        XCTAssertEqual(settle.label, "標示為已繳")
        let forecastEntry = app.buttons["home.entry.forecast"]
        XCTAssertTrue(forecastEntry.label.contains("最低 53,440 元"), "勾選前的最低餘額不對:\(forecastEntry.label)")

        settle.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "overview.settle.sample:rent", "取消已繳")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "勾選已繳之後圓圈沒有變成「取消已繳」")
        XCTAssertTrue(element(in: app, labelContaining: "房租，").exists, "已繳的房租不見了")
        XCTAssertTrue(element(in: app, labelContaining: "已繳，不計入預測").exists, "已繳的列沒有念出「已繳，不計入預測」")
        XCTAssertTrue(ScrollSupport.revealFully(forecastEntry, in: app), "找不到現金流預測入口")
        XCTAssertTrue(forecastEntry.label.contains("65,440"), "已繳之後現金流預測入口的最低餘額沒有由後端重算:\(forecastEntry.label)")

        // 預測頁是同一個功能:進去看到房租已繳。
        app.openHomeEntry("forecast")
        let pageButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "forecast.settle.sample:rent")).firstMatch
        XCTAssertTrue(pageButton.waitForExistence(timeout: 5), "預測頁沒有房租的已繳圓圈")
        XCTAssertEqual(pageButton.label, "取消已繳", "預測頁的狀態沒有跟首頁同步")
    }

    /// 單一入口放不下就整格單欄:預設字級兩欄(同一排)、AX5 單欄(上下排)。
    @MainActor
    func testEntriesAreTwoColumnsOnlyWhenTheyFit() throws {
        let normal = launchAtContentSize("UICTContentSizeCategoryL")
        _ = normal.descendants(matching: .any)["overview.composition"].waitForExistence(timeout: 10)
        let first = normal.buttons["home.entry.ledger"], second = normal.buttons["home.entry.accounts"]
        XCTAssertTrue(ScrollSupport.revealFully(first, in: normal), "沒有「記帳」入口")
        XCTAssertEqual(first.frame.minY.rounded(), second.frame.minY.rounded(), "預設字級入口格沒有兩欄:\(first.frame) \(second.frame)")
        normal.terminate()

        let large = launchAtContentSize("UICTContentSizeCategoryAccessibilityXXXL")
        _ = large.descendants(matching: .any)["overview.composition"].waitForExistence(timeout: 10)
        let a = large.buttons["home.entry.ledger"], b = large.buttons["home.entry.accounts"]
        XCTAssertTrue(ScrollSupport.revealFully(a, in: large), "AX5 沒有「記帳」入口")
        XCTAssertTrue(b.exists || ScrollSupport.revealFully(b, in: large), "AX5 沒有「帳戶」入口")
        XCTAssertNotEqual(a.frame.minY.rounded(), b.frame.minY.rounded(), "AX5 入口格沒有單欄:\(a.frame) \(b.frame)")
        XCTAssertGreaterThan(a.frame.width, large.windows.firstMatch.frame.width * 0.8, "AX5 入口格沒有用滿寬度")
    }

    /// 超支提示(#117):範例的預算額度餐飲 100、已花 120，所以有一個精簡的提示;點了切到統計 tab 的預算額度。
    /// 超支的明細(已花、預算額度)不在總覽。
    @MainActor
    func testOverBudgetChipOpensStatistics() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let chip = app.buttons["overview.overBudget"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "沒有超支提示")
        XCTAssertEqual(chip.label, "有 1 個分類支出已超出預算", "超支提示沒有念出完整的一句")
        XCTAssertFalse(element(in: app, labelContaining: "已花").exists, "總覽還有已花和預算額度")
        chip.tap()
        XCTAssertTrue(app.buttons["statistics.scope"].waitForExistence(timeout: 3), "超支提示沒有切到統計 tab")
    }

    /// 帳戶卡(#117、#190):信用卡卡片念成一句話(待繳總額、代墊與私帳、未出帳、繳款日)，橫向捲動;
    /// 點了切到記帳 tab、只剩該帳戶的收支明細，篩選按鈕顯示套用中的帳戶名稱。
    @MainActor
    func testAccountCardOpensTheLedgerForThatAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let card = app.buttons["overview.card.sample-card"]
        _ = app.descendants(matching: .any)["overview.composition"].waitForExistence(timeout: 10)
        XCTAssertTrue(ScrollSupport.revealFully(card, in: app), "帳戶卡片沒有信用卡")
        XCTAssertEqual(
            card.label,
            "iOS 測試信用卡，個人私帳，信用卡待繳總額 15,500 元，代墊 3,000 元，私帳 12,500 元，未出帳 3,500 元，每月 5 日繳款",
            "信用卡卡片沒有念出待繳總額、代墊與私帳、未出帳與繳款日"
        )
        card.tap()

        XCTAssertTrue(app.buttons["transactions.add"].waitForExistence(timeout: 5), "點帳戶卡片沒有切到記帳 tab")
        XCTAssertTrue(element(in: app, labelContaining: "耳機").waitForExistence(timeout: 5), "信用卡的收支明細不在清單上")
        XCTAssertTrue(element(in: app, labelContaining: "午餐").waitForNonExistence(timeout: 5), "帶入了信用卡的篩選，存款帳戶的收支明細還在")
        XCTAssertTrue(
            (app.buttons["transactions.filter"].value as? String ?? "").contains("iOS 測試信用卡"), "篩選按鈕的值沒有帳戶名稱:\(String(describing: app.buttons["transactions.filter"].value))"
        )
    }

    /// 帳戶卡橫向捲動:卡片不是一格一格往下排,而是同一排(同樣的 y),第一張之外的卡可以捲出來。
    @MainActor
    func testAccountCardsScrollHorizontally() throws {
        let app = launchAtContentSize("UICTContentSizeCategoryL")
        _ = app.descendants(matching: .any)["overview.composition"].waitForExistence(timeout: 10)
        let bank = app.buttons["overview.card.sample-bank"], card = app.buttons["overview.card.sample-card"]
        XCTAssertTrue(ScrollSupport.revealFully(bank, in: app), "沒有活存帳戶卡")
        XCTAssertTrue(card.exists, "沒有信用卡卡")
        XCTAssertEqual(bank.frame.minY.rounded(), card.frame.minY.rounded(), "帳戶卡沒有排在同一排:\(bank.frame) \(card.frame)")
        XCTAssertGreaterThan(card.frame.minX, bank.frame.maxX - 1, "第二張卡應該在第一張的右邊:\(bank.frame) \(card.frame)")
    }

    /// 摘要磚只在「放得下」時並排(#148):預設字級三格並排;
    /// XXL、XXXL、無障礙字級放不下，整排改單欄——標籤不折行、金額不被縮小或切到,而且是整排一起改,不是只有某一格。
    @MainActor
    func testTilesAndAccountCardsAreSideBySideOnlyWhenTheyFit() throws {
        let app = launchAtContentSize("UICTContentSizeCategoryL")

        let tiles = [("真實可支配現金", "21,500 元"), ("當月淨收支", "44,000 元"), ("信用卡待繳", "28,500 元")]
            .map { row($0.0, value: $0.1, in: app) }
        XCTAssertTrue(tiles[0].waitForExistence(timeout: 5), "沒有看到數字磚")
        XCTAssertEqual(Set(tiles.map { $0.frame.minY.rounded() }).count, 1, "預設字級三格數字磚沒有橫排:\(tiles.map(\.frame))")
        XCTAssertLessThan(tiles[0].frame.minX, tiles[1].frame.minX)
        XCTAssertLessThan(tiles[1].frame.minX, tiles[2].frame.minX)

    }

    @MainActor
    func testTilesBecomeSingleColumnAtXXL() throws {
        try assertTilesAreSingleColumn(at: "UICTContentSizeCategoryXXL", labelsStayOnOneLine: true)
    }

    @MainActor
    func testTilesBecomeSingleColumnAtXXXL() throws {
        try assertTilesAreSingleColumn(at: "UICTContentSizeCategoryXXXL", labelsStayOnOneLine: true)
    }

    @MainActor
    func testTilesBecomeSingleColumnAtAX5() throws {
        try assertTilesAreSingleColumn(at: "UICTContentSizeCategoryAccessibilityXXXL", labelsStayOnOneLine: true)
    }

    /// 放不下就整排單欄:三格上下堆疊、同樣寬;每格標籤只有一行(不再折成「可支配／現金」兩行)、金額與組成明細沒有被切到。
    @MainActor
    private func assertTilesAreSingleColumn(at category: String, labelsStayOnOneLine: Bool) throws {
        let app = launchAtContentSize(category)
        let tiles = [("真實可支配現金", "21,500 元"), ("當月淨收支", "44,000 元"), ("信用卡待繳", "28,500 元")]
            .map { row($0.0, value: $0.1, in: app) }
        XCTAssertTrue(tiles[0].waitForExistence(timeout: 5), "沒有看到數字磚")
        for _ in 0..<6 where !tiles.allSatisfy(\.exists) { app.swipeUp() }
        XCTAssertTrue(tiles.allSatisfy(\.exists), "\(category):沒有看到三格數字磚")
        XCTAssertEqual(Set(tiles.map { $0.frame.minY.rounded() }).count, 3, "\(category):三格數字磚沒有上下堆疊:\(tiles.map(\.frame))")
        XCTAssertEqual(Set(tiles.map { $0.frame.width.rounded() }).count, 1, "\(category):單欄的三格不一樣寬:\(tiles.map(\.frame))")
        XCTAssertGreaterThan(tiles[0].frame.width, app.windows.firstMatch.frame.width * 0.8, "\(category):單欄沒有用滿寬度")

        for (index, tile) in tiles.enumerated() {
            XCTAssertTrue(ScrollSupport.revealFully(tile, in: app), "\(category):第 \(index + 1) 格捲不到整格都看得到:\(tile.frame)")
            let bands = try PixelAnalysis.inkBands(of: tile.screenshot().image)
            XCTAssertFalse(bands.isEmpty, "\(category):第 \(index + 1) 格看不到字")
            // 標籤一行:標籤不折成「可支配／現金」兩行(下面還有組成明細,所以不能數墨跡的行數,改用 OCR 看標籤是不是完整一行)。
            let lines = try TextRecognition.lines(in: tile.screenshot().image)
            let label = ["可支配現金", "當月淨收支", "信用卡待繳"][index]
            XCTAssertTrue(lines.contains { $0.contains(label) }, "\(category):第 \(index + 1) 格標籤折行了，辨識到:\(lines)")
            // 金額沒有被切到:墨跡沒有貼到元素邊緣。
            let width = Int(tile.screenshot().image.size.width * tile.screenshot().image.scale)
            XCTAssertTrue(bands.allSatisfy { $0.minX > 4 && $0.maxX < width - 4 }, "\(category):第 \(index + 1) 格的字貼到邊緣(可能被切到):\(bands) 寬度 \(width)")
        }
    }

    @MainActor
    private func launchAtContentSize(_ category: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession", "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        signIn(app)
        return app
    }

    /// 視角在 toolbar 的篩選按鈕(#63):點按鈕再選，按鈕的 VoiceOver 值是目前的視角;選過的視角重開 app 之後沿用。
    @MainActor
    func testScopeFilterShowsSubtitleAndIsRemembered() throws {
        let app = launch(resettingSession: true)
        signIn(app)

        let filter = app.buttons["overview.scope"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "toolbar 沒有視角的篩選按鈕")
        XCTAssertEqual(filter.label, "視角", "篩選按鈕的 VoiceOver 標籤不是「視角」")
        XCTAssertEqual(filter.value as? String, "全部", "篩選按鈕的 VoiceOver 值不是目前的視角")

        choose("家庭公帳", from: filter, in: app)
        XCTAssertTrue(element(in: app, labelContaining: "當月淨收支(家庭公帳)").waitForExistence(timeout: 5), "切到家庭視角後，當月淨收支的標題沒有跟著變")
        XCTAssertEqual(filter.value as? String, "家庭公帳", "切換視角後篩選按鈕的 VoiceOver 值沒有跟著變")
        app.terminate()

        // 不帶 `-resetSession`:session 和選過的視角都還在。
        let relaunched = launch(resettingSession: false)
        let relaunchedFilter = relaunched.buttons["overview.scope"]
        XCTAssertTrue(relaunchedFilter.waitForExistence(timeout: 5), "重開 app 之後沒有看到篩選按鈕")
        XCTAssertEqual(relaunchedFilter.value as? String, "家庭公帳", "重開 app 之後沒有沿用選過的視角")
    }

    /// 點 toolbar 的篩選按鈕打開選單，再點選項。
    @MainActor
    private func choose(_ option: String, from filter: XCUIElement, in app: XCUIApplication) {
        filter.tap()
        let item = app.buttons[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "視角選單裡沒有「\(option)」")
        item.tap()
    }

    @MainActor
    private func launch(resettingSession: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (resettingSession ? ["-resetSession"] : [])
        app.launch()
        return app
    }

    /// 摘要和超支警告的一般列：VoiceOver 念標籤，值是金額，例如標籤「當月淨收支」、值「44,000 元」。
    @MainActor
    private func row(_ label: String, value: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value BEGINSWITH %@", label, value)).firstMatch
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
