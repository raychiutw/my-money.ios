import XCTest

/// 「總覽」tab。資料來自 MyMoneyTestSupport 的範例資料(日期相對於今天，不連網路)。
final class OverviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 從總覽記一筆 250 元 → 當月淨收支和最近交易跟著更新;「查看全部」進入交易 tab。
    @MainActor
    func testQuickEntryUpdatesMonthNetAndRecent() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        // 範例：收入 45,000,支出 120 + 880(信用卡還款不算)。
        XCTAssertTrue(row("當月淨收支", value: "44,000 元", in: app).waitForExistence(timeout: 5), "沒有看到當月淨收支")

        app.buttons["overview.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("250")
        app.chooseQuickEntryAccount()
        app.buttons["quickEntry.save"].tap()

        XCTAssertTrue(row("當月淨收支", value: "43,750 元", in: app).waitForExistence(timeout: 5), "記一筆後當月淨收支沒有更新")
        // 最近交易在畫面下方;List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let recent = element(in: app, labelContaining: "支出 250 元")
        for _ in 0..<5 where !recent.exists { app.swipeUp() }
        XCTAssertTrue(recent.exists, "記一筆後最近交易沒有更新")

        // 區塊標題右邊是「…」玻璃圓鈕(#134):點開選單，「查看全部交易」進入交易 tab。
        let more = app.buttons["overview.recent.more"]
        for _ in 0..<5 where !more.isHittable { app.swipeUp() }
        more.tap()
        app.buttons["查看全部交易"].tap()
        XCTAssertTrue(app.buttons["transactions.add"].waitForExistence(timeout: 3), "最近的「查看全部交易」沒有進入交易 tab")
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
        // 公式明細在帳戶頁、週期收支、儲蓄目標和統計頁，總覽不寫。
        for formula in ["銀行存款 $50,000", "已扣掉分攤平滑", "收入 $45,000"] {
            XCTAssertFalse(element(in: app, labelContaining: formula).exists, "總覽還有公式明細「\(formula)」")
        }
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

    /// 最近交易只有圖示、名稱和金額(#117):整列念成一句話「分類，備註，收支金額」;日期、帳戶、記帳人在交易頁。
    @MainActor
    func testRecentTransactionReadsAsOneSentence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let headphones = app.descendants(matching: .any)["購物，耳機，支出 880 元"]
        for _ in 0..<5 where !headphones.exists { app.swipeUp() }
        XCTAssertTrue(headphones.exists, "最近交易的耳機沒有念成一句「分類，備註，金額」")
        XCTAssertFalse(element(in: app, labelContaining: "帳戶 iOS").exists, "最近交易還顯示帳戶")
        XCTAssertFalse(element(in: app, labelContaining: "記帳人").exists, "最近交易還顯示記帳人")
    }

    /// 帳戶卡片(#117):信用卡卡片念成一句話(待繳總額、每月幾日繳款)，點進去是信用卡詳細頁(#73)。
    @MainActor
    func testCreditCardRowOpensDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let card = app.buttons["overview.card.sample-card"]
        _ = card.waitForExistence(timeout: 5)
        for _ in 0..<5 where !(card.exists && card.isHittable) { app.swipeUp() }
        XCTAssertTrue(card.exists, "帳戶卡片沒有信用卡")
        XCTAssertEqual(card.label, "iOS 測試信用卡，信用卡待繳總額 15,500 元，每月 5 日繳款", "信用卡卡片沒有念出待繳總額與繳款日")
        card.tap()
        XCTAssertTrue(app.navigationBars["iOS 測試信用卡"].waitForExistence(timeout: 3), "點帳戶卡片的信用卡沒有進入詳細頁")
        // 詳細頁的欄位是 `LabeledContent`,標籤和值合成一個元素。
        XCTAssertTrue(app.staticTexts["信用卡待繳總額、$15,500"].waitForExistence(timeout: 3), "從總覽進入的詳細頁沒有信用卡待繳總額")
    }

    /// 總覽跟設計稿一致(#124):三格數字磚橫排、帳戶卡片兩欄、淨可用餘額是很大的數字。
    /// 真機的字級常常不是預設的 L:XXL 時數字磚與卡片不能掉成單欄(設計稿是橫排)，要到更大的字級才上下堆疊。
    /// 只在預設字級截圖驗收不夠，所以這裡用 XXL 實際量位置。
    @MainActor
    func testTilesAndAccountCardsStaySideBySideAtXXL() throws {
        let app = launchAtContentSize("UICTContentSizeCategoryXXL")

        let tiles = [("真實可支配現金", "21,500 元"), ("當月淨收支", "44,000 元"), ("信用卡待繳", "28,500 元")]
            .map { row($0.0, value: $0.1, in: app) }
        XCTAssertTrue(tiles[0].waitForExistence(timeout: 5), "沒有看到數字磚")
        XCTAssertEqual(Set(tiles.map { $0.frame.minY.rounded() }).count, 1, "XXL 時三格數字磚沒有橫排:\(tiles.map(\.frame))")
        XCTAssertLessThan(tiles[0].frame.minX, tiles[1].frame.minX)
        XCTAssertLessThan(tiles[1].frame.minX, tiles[2].frame.minX)

        // 帳戶卡片兩欄:銀行存款帳戶與第一張信用卡在同一排。
        let bank = element(in: app, labelContaining: "iOS 測試存款，銀行存款帳戶")
        let card = app.buttons["overview.card.sample-card"]
        for _ in 0..<6 where !(bank.exists && card.exists) { app.swipeUp() }
        XCTAssertTrue(bank.exists && card.exists, "沒有看到帳戶卡片")
        XCTAssertEqual(bank.frame.minY.rounded(), card.frame.minY.rounded(), "XXL 時帳戶卡片沒有兩欄:\(bank.frame) \(card.frame)")
    }

    /// 反過來:無障礙字級(AX5)放不下橫排時，數字磚與帳戶卡片上下堆疊，數字不截斷。
    @MainActor
    func testTilesStackAtAccessibilityContentSize() throws {
        let app = launchAtContentSize("UICTContentSizeCategoryAccessibilityXXXL")

        let first = row("真實可支配現金", value: "21,500 元", in: app)
        let second = row("當月淨收支", value: "44,000 元", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5), "沒有看到數字磚")
        for _ in 0..<4 where !second.exists { app.swipeUp() }
        XCTAssertTrue(second.exists, "沒有看到第二格數字磚")
        XCTAssertNotEqual(first.frame.minY.rounded(), second.frame.minY.rounded(), "AX5 時數字磚沒有上下堆疊")
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
        XCTAssertTrue(element(in: app, labelContaining: "當月淨收支(家庭)").waitForExistence(timeout: 5), "切到家庭視角後，當月淨收支的標題沒有跟著變")
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
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", label, value)).firstMatch
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
