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
        app.buttons["quickEntry.save"].tap()

        XCTAssertTrue(row("當月淨收支", value: "43,750 元", in: app).waitForExistence(timeout: 5), "記一筆後當月淨收支沒有更新")
        // 最近交易在畫面下方;List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let recent = element(in: app, labelContaining: "支出 250 元")
        for _ in 0..<5 where !recent.exists { app.swipeUp() }
        XCTAssertTrue(recent.exists, "記一筆後最近交易沒有更新")

        let showAll = app.buttons["查看全部"]
        for _ in 0..<5 where !showAll.isHittable { app.swipeUp() }
        showAll.tap()
        XCTAssertTrue(app.buttons["transactions.add"].waitForExistence(timeout: 3), "「查看全部」沒有進入交易 tab")
    }

    /// 摘要只有一個主數字(#75):淨可用餘額在最上面，真實可支配現金、當月淨收支是一般列;沒有公式明細。
    /// 超支警告每個超支的分類一列：分類名稱和超支金額。
    @MainActor
    func testSummaryHasOneMainNumberAndOverBudgetRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let available = element(in: app, labelContaining: "淨可用餘額 21,500 元")
        XCTAssertTrue(available.waitForExistence(timeout: 5), "沒有淨可用餘額")
        for (label, value) in [("真實可支配現金", "21,500 元"), ("當月淨收支", "44,000 元")] {
            let summaryRow = row(label, value: value, in: app)
            XCTAssertTrue(summaryRow.exists, "摘要沒有「\(label) \(value)」這一列")
            XCTAssertLessThan(available.frame.minY, summaryRow.frame.minY, "淨可用餘額不在「\(label)」上面")
        }
        // 公式明細在帳戶頁、週期收支、儲蓄目標和統計頁，總覽不寫。
        for formula in ["銀行存款 $50,000", "已扣掉分攤平滑", "收入 $45,000"] {
            XCTAssertFalse(element(in: app, labelContaining: formula).exists, "總覽還有公式明細「\(formula)」")
        }

        // 範例的預算額度：餐飲 100,已花 120。
        let overBudget = row("餐飲", value: "超支 20 元", in: app)
        for _ in 0..<5 where !overBudget.exists { app.swipeUp() }
        XCTAssertTrue(overBudget.exists, "超支警告沒有「餐飲」這一列")
        XCTAssertTrue(element(in: app, labelContaining: "有 1 個分類支出已超出預算").exists, "超支警告沒有標題")
        XCTAssertFalse(element(in: app, labelContaining: "已花").exists, "超支警告還有已花和預算額度")
    }

    /// 最近交易跟交易頁用同一種交易記錄列(#72):整列念成一句完整的話，自己記的不念記帳人;
    /// 總覽多念日期(#79)。
    @MainActor
    func testRecentTransactionReadsAsOneSentence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let headphones = app.descendants(matching: .any)["購物，耳機，\(Self.taipeiToday())，帳戶 iOS 測試信用卡，個人私帳，支出 880 元"]
        for _ in 0..<5 where !headphones.exists { app.swipeUp() }
        XCTAssertTrue(headphones.exists, "最近交易的耳機沒有念成一句完整的話")
        XCTAssertFalse(element(in: app, labelContaining: "記帳人").exists, "自己記的交易記錄還顯示記帳人")
    }

    /// 台灣時間的今天，格式跟清單的日期一樣(同一年省略年份),例如「9月28日」。
    private static func taipeiToday() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = calendar.dateComponents([.month, .day], from: .now)
        return "\(day.month!)月\(day.day!)日"
    }

    /// 帳戶一覽的信用卡跟帳戶頁用同一種精簡列(#73):整列念成一句話，點進去是信用卡詳細頁。
    @MainActor
    func testCreditCardRowOpensDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        let card = app.buttons["overview.card.sample-card"]
        _ = card.waitForExistence(timeout: 5)
        for _ in 0..<5 where !(card.exists && card.isHittable) { app.swipeUp() }
        XCTAssertTrue(card.exists, "帳戶一覽的信用卡不是導覽連結")
        XCTAssertEqual(card.label, "iOS 測試信用卡，個人卡，信用卡待繳總額 15,500 元，每月 5 日繳款", "帳戶一覽的信用卡不是精簡列")
        card.tap()
        XCTAssertTrue(app.navigationBars["iOS 測試信用卡"].waitForExistence(timeout: 3), "點帳戶一覽的信用卡沒有進入詳細頁")
        // 詳細頁的欄位是 `LabeledContent`,標籤和值合成一個元素。
        XCTAssertTrue(app.staticTexts["信用卡待繳總額、$15,500"].waitForExistence(timeout: 3), "從總覽進入的詳細頁沒有信用卡待繳總額")
    }

    /// 視角在 toolbar 的篩選按鈕(#63):點按鈕再選，導覽列副標題顯示目前的視角;選過的視角重開 app 之後沿用。
    @MainActor
    func testScopeFilterShowsSubtitleAndIsRemembered() throws {
        let app = launch(resettingSession: true)
        signIn(app)

        let filter = app.buttons["overview.scope"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "toolbar 沒有視角的篩選按鈕")
        XCTAssertEqual(filter.label, "視角", "篩選按鈕的 VoiceOver 標籤不是「視角」")
        XCTAssertEqual(filter.value as? String, "全部", "篩選按鈕的 VoiceOver 值不是目前的視角")
        XCTAssertTrue(subtitle("全部", in: app).waitForExistence(timeout: 3), "導覽列副標題沒有顯示目前的視角")

        choose("家庭", from: filter, in: app)
        XCTAssertTrue(element(in: app, labelContaining: "當月淨收支(家庭)").waitForExistence(timeout: 5), "切到家庭視角後，當月淨收支的標題沒有跟著變")
        XCTAssertTrue(subtitle("家庭", in: app).exists, "切換視角後導覽列副標題沒有跟著變")
        XCTAssertEqual(filter.value as? String, "家庭", "切換視角後篩選按鈕的 VoiceOver 值沒有跟著變")
        app.terminate()

        // 不帶 `-resetSession`:session 和選過的視角都還在。
        let relaunched = launch(resettingSession: false)
        XCTAssertTrue(subtitle("家庭", in: relaunched).waitForExistence(timeout: 5), "重開 app 之後沒有沿用選過的視角")
    }

    /// 點 toolbar 的篩選按鈕打開選單，再點選項。
    @MainActor
    private func choose(_ option: String, from filter: XCUIElement, in app: XCUIApplication) {
        filter.tap()
        let item = app.buttons[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "視角選單裡沒有「\(option)」")
        item.tap()
    }

    /// 導覽列副標題(`navigationSubtitle`)。
    @MainActor
    private func subtitle(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts[text]
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
