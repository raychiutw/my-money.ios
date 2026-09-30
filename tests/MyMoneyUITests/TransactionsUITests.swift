import XCTest

/// 「交易」tab 與「記一筆」。資料來自 MyMoneyTestSupport 的 `SampleTransactions`(日期相對於今天，不連網路)。
final class TransactionsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 列表顯示本月的交易記錄;記一筆 250 元後出現在列表上。
    @MainActor
    func testListShowsThisMonthAndQuickEntryAddsTransaction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["交易"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "支出 880 元").waitForExistence(timeout: 5), "沒有看到本月的交易記錄")
        XCTAssertTrue(element(in: app, labelContaining: "收入 45,000 元").exists)
        XCTAssertTrue(element(in: app, labelContaining: "個人私帳").exists)
        // 預設的範圍是本月 1 號到台灣時間的今天。CI 的模擬器在 UTC,以前會顯示成前一天。
        XCTAssertTrue(
            subtitle("全部・\(Self.taipeiThisMonthPeriod())", in: app).exists,
            "導覽列副標題不是本月 1 號到台灣時間的今天(\(Self.taipeiThisMonthPeriod()))"
        )

        app.buttons["transactions.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("250")
        XCTAssertFalse(element(in: app, labelContaining: "(銀行存款帳戶)").exists, "記一筆的帳戶選擇列還帶著類型")
        app.buttons["quickEntry.save"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "支出 250 元").waitForExistence(timeout: 5), "記一筆後沒有出現在列表上")
    }

    /// 篩選收進 toolbar 篩選按鈕打開的「篩選」sheet(#74):清單上方沒有分段控制，導覽列副標題一律顯示目前的範圍。
    /// 在 sheet 裡改類型後按「完成」,清單、副標題和交易記錄的筆數都更新;再改一次按「取消」,全部不變。
    @MainActor
    func testFilterSheetAppliesOnDoneAndCancelKeepsFilter() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["交易"].tap()

        let period = Self.taipeiThisMonthPeriod()
        XCTAssertTrue(element(in: app, labelContaining: "支出 880 元").waitForExistence(timeout: 5), "沒有看到本月的交易記錄")
        XCTAssertTrue(subtitle("全部・\(period)", in: app).waitForExistence(timeout: 3), "導覽列副標題沒有顯示目前的範圍(全部・\(period))")
        XCTAssertEqual(app.collectionViews.firstMatch.segmentedControls.count, 0, "交易頁的清單上方還有分段控制")
        XCTAssertTrue(app.staticTexts["交易記錄(4)"].exists, "交易記錄的筆數不在 section 的標題")

        let filter = app.buttons["transactions.filter"]
        XCTAssertTrue(filter.exists, "toolbar 沒有篩選按鈕")
        XCTAssertEqual(filter.label, "篩選", "篩選按鈕的 VoiceOver 標籤不是「篩選」")
        filter.tap()
        let sheet = app.navigationBars["篩選"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "點篩選按鈕沒有打開「篩選」sheet")
        XCTAssertTrue(app.segmentedControls.buttons["家庭"].exists, "篩選 sheet 裡沒有視角的分段控制")
        // 迄日的 DatePicker 是台灣時間的今天。CI 的模擬器在 UTC,以前會顯示成前一天。
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "value == %@", Self.taipeiToday())).firstMatch.exists,
            "迄日不是台灣時間的今天(\(Self.taipeiToday()))"
        )
        choose("僅收入", from: app.buttons["transactionFilter.type"], in: app)
        sheet.buttons["完成"].tap()

        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3), "按完成後篩選 sheet 沒有關閉")
        XCTAssertTrue(subtitle("全部・\(period)・收入", in: app).waitForExistence(timeout: 3), "按完成後副標題沒有加上類型")
        XCTAssertTrue(element(in: app, labelContaining: "收入 45,000 元").exists, "按完成後清單沒有收入")
        XCTAssertFalse(element(in: app, labelContaining: "支出 880 元").exists, "按完成後清單還有支出")
        XCTAssertTrue(app.staticTexts["交易記錄(1)"].exists, "按完成後交易記錄的筆數沒有更新")

        // 改成僅支出再按取消：清單和副標題都不變。
        filter.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "沒有再次打開「篩選」sheet")
        choose("僅支出", from: app.buttons["transactionFilter.type"], in: app)
        sheet.buttons["取消"].tap()

        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3), "按取消後篩選 sheet 沒有關閉")
        XCTAssertTrue(subtitle("全部・\(period)・收入", in: app).exists, "按取消後副標題變了")
        XCTAssertTrue(element(in: app, labelContaining: "收入 45,000 元").exists, "按取消後清單變了")
        XCTAssertFalse(element(in: app, labelContaining: "支出 880 元").exists, "按取消後清單變了")
    }

    /// 交易記錄列一行一個欄位(#72):VoiceOver 把整列念成一句完整的話(分類、備註、帳戶、歸屬、收支方向與金額),
    /// 自己記的不念記帳人;分組標頭是「9月28日週一」這種系統格式，不是「09/28」。
    @MainActor
    func testRowReadsAsOneSentenceAndDayHeaderUsesSystemFormat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["交易"].tap()

        let lunch = app.descendants(matching: .any)["餐飲，午餐，帳戶 iOS 測試存款，家庭公帳，支出 120 元"]
        XCTAssertTrue(lunch.waitForExistence(timeout: 5), "午餐那一列沒有念成一句完整的話")
        XCTAssertTrue(
            app.staticTexts[Self.taipeiTodayHeader()].exists,
            "分組標頭不是系統格式(\(Self.taipeiTodayHeader()))"
        )
        // 範例資料都是自己記的，所以清單裡沒有任何一列念出記帳人(搜尋欄的提示也有「記帳人」,不在清單裡)。
        let list = app.collectionViews.firstMatch
        XCTAssertFalse(
            list.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "記帳人")).firstMatch.exists,
            "自己記的交易記錄還顯示記帳人"
        )

        // 沒有備註的列用分類名稱，不重複念兩次。薪資在本月 1 號，在清單最下面。
        let salary = app.descendants(matching: .any)["薪資，帳戶 iOS 測試存款，家庭公帳，收入 45,000 元"]
        for _ in 0..<5 where !salary.exists { app.swipeUp() }
        XCTAssertTrue(salary.exists, "沒有備註的列沒有用分類名稱念成一句話")
    }

    /// 記一筆的支出／收入在 sheet 導覽列中間(分段控制);歸屬是表單裡一般的選擇列，表單裡沒有分段控制(#65)。
    /// 切到收入、歸屬選個人私帳，記一筆 250 元後，列表上是一筆個人私帳的收入。
    @MainActor
    func testQuickEntryTypeInNavigationBarAndOwnershipRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["交易"].tap()

        app.buttons["transactions.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開記一筆")
        let type = app.navigationBars.segmentedControls.firstMatch
        XCTAssertTrue(type.exists, "支出／收入不在導覽列中間")
        XCTAssertTrue(type.buttons["支出"].isSelected, "記一筆預設不是支出")
        type.buttons["收入"].tap()

        let form = app.collectionViews.containing(.textField, identifier: "quickEntry.amount").firstMatch
        XCTAssertEqual(form.segmentedControls.count, 0, "記一筆的表單裡還有分段控制")
        choose("個人私帳", from: app.buttons["quickEntry.ownership"], in: app)

        amount.tap()
        amount.typeText("250")
        app.buttons["quickEntry.save"].tap()
        let added = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "收入 250 元", "個人私帳")
        ).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5), "記一筆後列表上沒有個人私帳的收入 250 元")
    }

    /// 點一筆交易記錄編輯歸屬;左滑刪除(先確認);信用卡還款只有鎖定標記;搜尋只留下符合的紀錄。
    /// 編輯金額見 `testEditingAmountReplacesOriginalValue`。
    @MainActor
    func testEditDeleteRepaymentLockAndSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["交易"].tap()

        let headphones = element(in: app, labelContaining: "支出 880 元")
        XCTAssertTrue(headphones.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, labelContaining: "個人私帳").exists)
        headphones.tap()
        let ownership = app.buttons["quickEntry.ownership"]
        XCTAssertTrue(ownership.waitForExistence(timeout: 3), "編輯交易記錄沒有歸屬的選擇列")
        choose("家庭公帳", from: ownership, in: app)
        app.buttons["quickEntry.save"].tap()
        // 範例資料裡只有耳機是個人私帳;改成家庭公帳之後，列表上就沒有個人私帳了。
        XCTAssertTrue(element(in: app, labelContaining: "個人私帳").waitForNonExistence(timeout: 5), "編輯後歸屬沒有更新")

        // 上面有摘要，列表可能在畫面下方。iOS 26 的 tab bar 浮在內容上，被它蓋住的列 isHittable 仍然是 true,
        // 左滑卻會滑在 tab bar 上:先捲到畫面上方 3/4 以內，左滑才滑得出「刪除」。
        let lunch = element(in: app, labelContaining: "支出 120 元")
        let screenBottom = app.windows.firstMatch.frame.maxY
        for _ in 0..<5 where !(lunch.exists && lunch.frame.maxY < screenBottom * 0.75) { app.swipeUp() }
        lunch.swipeLeft()
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["確定要刪除這筆交易記錄嗎？"].waitForExistence(timeout: 3), "沒有先確認就刪除")
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(lunch.waitForNonExistence(timeout: 5), "刪除後還在列表上")

        // 系統分類的交易記錄只顯示鎖定標記，不再有說明文字(#63);VoiceOver 念出不能編輯或刪除。
        let locked = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "信用卡還款", "系統紀錄，不能編輯或刪除")
        ).firstMatch
        for _ in 0..<5 where !locked.exists { app.swipeUp() }
        XCTAssertTrue(locked.exists, "信用卡還款沒有鎖定標記，或 VoiceOver 沒有念出「系統紀錄，不能編輯或刪除」")

        // 搜尋欄在最上面，捲回去才點得到。
        let search = app.searchFields.firstMatch
        for _ in 0..<5 where !(search.exists && search.isHittable) { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("薪資")
        XCTAssertTrue(element(in: app, labelContaining: "收入 45,000 元").waitForExistence(timeout: 3))
        XCTAssertFalse(element(in: app, labelContaining: "支出 880 元").exists, "搜尋後還看得到不符合的紀錄")
    }

    /// 已經有值的金額欄，直接輸入就取代原值(#32):耳機 880 → 990 → 770。
    ///
    /// 兩條路徑都要走：表單一打開金額欄就自動取得焦點(`.task`),直接輸入;把焦點移到備註後再點金額欄。
    @MainActor
    func testEditingAmountReplacesOriginalValue() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["交易"].tap()

        let headphones = element(in: app, labelContaining: "支出 880 元")
        XCTAssertTrue(headphones.waitForExistence(timeout: 5))
        headphones.tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "表單打開時金額欄沒有取得焦點")
        app.typeText("990")
        XCTAssertEqual(amount.value as? String, "990", "自動取得焦點時，輸入的數字沒有取代原值")

        app.textFields["quickEntry.note"].tap()
        amount.tap()
        amount.typeText("770")
        XCTAssertEqual(amount.value as? String, "770", "點選金額欄時，輸入的數字沒有取代原值")

        app.buttons["quickEntry.save"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "支出 770 元").waitForExistence(timeout: 5), "編輯後金額沒有更新")
    }

    /// 記一筆：焦點在備註欄時，按鍵盤上的「完成」會收起鍵盤(#61)。
    ///
    /// 以前「完成」只清掉金額欄的焦點，備註欄沒有納入同一個 focus 狀態，按了沒反應。
    @MainActor
    func testDoneOnQuickEntryNoteDismissesKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["交易"].tap()

        app.buttons["transactions.add"].tap()
        let note = app.textFields["quickEntry.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "沒有打開記一筆")
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "點備註欄後沒有出現鍵盤")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "備註欄按「完成」後，鍵盤沒有收起")
    }

    /// 記一筆：捲動表單會收起鍵盤(#61),表單仍然開著。
    @MainActor
    func testScrollingQuickEntryDismissesKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["交易"].tap()

        app.buttons["transactions.add"].tap()
        let note = app.textFields["quickEntry.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "沒有打開記一筆")
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "點備註欄後沒有出現鍵盤")
        // 在鍵盤上方按住表單往上拖。`swipeUp()` 太快，表單不會開始捲動;在最上面往下拖會拉動 sheet 本身。
        let form = app.collectionViews.containing(.textField, identifier: "quickEntry.note").firstMatch
        form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "捲動表單後，鍵盤沒有收起")
        XCTAssertTrue(app.buttons["quickEntry.save"].exists, "捲動表單時把記一筆關掉了")
    }

    /// 台灣時間的今天，格式跟 DatePicker 的值一樣，例如「2026年9月28日」。
    private static func taipeiToday() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = calendar.dateComponents([.year, .month, .day], from: .now)
        return "\(day.year!)年\(day.month!)月\(day.day!)日"
    }

    /// 台灣時間的本月 1 號到今天，格式跟導覽列副標題一樣，例如「9月1日–9月28日」。
    private static func taipeiThisMonthPeriod() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = calendar.dateComponents([.month, .day], from: .now)
        return "\(day.month!)月1日–\(day.month!)月\(day.day!)日"
    }

    /// 台灣時間的今天，格式跟交易頁的分組標頭一樣，例如「9月28日週一」。
    private static func taipeiTodayHeader() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = calendar.dateComponents([.month, .day, .weekday], from: .now)
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        return "\(day.month!)月\(day.day!)日週\(weekdays[day.weekday! - 1])"
    }

    /// 點表單的選擇列打開選單，再點選項。sheet 底下列表的列也含有同樣的文字，所以只找選單裡的選項
    /// (直接放在 cell 裡的按鈕)。
    @MainActor
    private func choose(_ option: String, from picker: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "表單沒有這個選擇列")
        picker.tap()
        let item = app.cells.children(matching: .button)[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "選單裡沒有「\(option)」")
        item.tap()
    }

    /// 導覽列副標題(`navigationSubtitle`)。
    @MainActor
    /// 工具列只有篩選、記一筆、頭像三顆，沒有系統自動收成的「…」;匯出 CSV 是列表最底下的一列(ADR-0004、#86)。
    @MainActor
    func testToolbarHasThreeButtonsAndExportIsTheLastRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["交易"].tap()
        XCTAssertTrue(app.buttons["transactions.filter"].waitForExistence(timeout: 5), "沒有篩選按鈕")
        let toolbar = app.navigationBars.firstMatch
        for id in ["transactions.filter", "transactions.add", "toolbar.me"] {
            XCTAssertTrue(toolbar.buttons[id].exists, "工具列缺少 \(id)")
        }
        XCTAssertEqual(toolbar.buttons.count, 3, "工具列不是三顆按鈕")
        XCTAssertFalse(toolbar.buttons["transactions.export"].exists, "匯出 CSV 還在工具列")

        let export = app.buttons["transactions.export"]
        for _ in 0..<12 where !(export.exists && export.isHittable) { app.swipeUp() }
        XCTAssertTrue(export.exists && export.isHittable, "列表最底下沒有「匯出 CSV」")
        XCTAssertEqual(export.label, "匯出 CSV")
    }

    /// 記一筆的「帳戶」列只顯示名稱，點了推入清單頁;清單每列有名稱與類型，選了自動返回(ADR-0004、#88)。
    @MainActor
    func testAccountIsChosenOnAPushedListPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["交易"].tap()
        app.buttons["transactions.add"].tap()
        func accountRow() -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "帳戶")).firstMatch
        }
        XCTAssertTrue(accountRow().waitForExistence(timeout: 5), "記一筆沒有「帳戶」列")
        XCTAssertTrue(accountRow().label.contains("iOS 測試存款"), "「帳戶」列的值不是預設的第一個帳戶:\(accountRow().label)")

        accountRow().tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "iOS 測試信用卡")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3), "沒有推入帳戶清單頁")
        XCTAssertTrue(card.label.contains("信用卡"), "清單頁的列沒有類型副標題:\(card.label)")

        card.tap()
        XCTAssertTrue(accountRow().waitForExistence(timeout: 3), "選了帳戶之後沒有自動返回表單")
        XCTAssertTrue(accountRow().label.contains("iOS 測試信用卡"), "返回之後「帳戶」列沒有顯示新選的帳戶:\(accountRow().label)")
    }

    private func subtitle(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts[text]
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
