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
        // 迄日是台灣時間的今天。CI 的模擬器在 UTC,以前會顯示成前一天。
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "value == %@", Self.taipeiToday())).firstMatch.exists,
            "迄日不是台灣時間的今天(\(Self.taipeiToday()))"
        )

        app.buttons["transactions.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("250")
        app.buttons["quickEntry.save"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "支出 250 元").waitForExistence(timeout: 5), "記一筆後沒有出現在列表上")
    }

    /// 點一筆交易記錄編輯歸屬;左滑刪除(先確認);信用卡還款顯示受保護的說明;搜尋只留下符合的紀錄。
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
        let shared = app.buttons["家庭公帳"]
        XCTAssertTrue(shared.waitForExistence(timeout: 3))
        shared.tap()
        app.buttons["quickEntry.save"].tap()
        // 範例資料裡只有耳機是個人私帳;改成家庭公帳之後，列表上就沒有個人私帳了。
        XCTAssertTrue(element(in: app, labelContaining: "個人私帳").waitForNonExistence(timeout: 5), "編輯後歸屬沒有更新")

        // 上面有篩選和加總列，列表在畫面下方。iOS 26 的 tab bar 浮在內容上，被它蓋住的列 isHittable 仍然是 true,
        // 左滑卻會滑在 tab bar 上:先捲到畫面上方 3/4 以內，左滑才滑得出「刪除」。
        let lunch = element(in: app, labelContaining: "支出 120 元")
        let screenBottom = app.windows.firstMatch.frame.maxY
        for _ in 0..<5 where !(lunch.exists && lunch.frame.maxY < screenBottom * 0.75) { app.swipeUp() }
        lunch.swipeLeft()
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["確定要刪除這筆交易記錄嗎？"].waitForExistence(timeout: 3), "沒有先確認就刪除")
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(lunch.waitForNonExistence(timeout: 5), "刪除後還在列表上")

        let locked = element(in: app, labelContaining: "受保護")
        for _ in 0..<5 where !locked.exists { app.swipeUp() }
        XCTAssertTrue(locked.exists, "信用卡還款沒有顯示受保護的說明")

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

    /// 台灣時間的今天，格式跟 DatePicker 的值一樣，例如「2026年9月28日」。
    private static func taipeiToday() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = calendar.dateComponents([.year, .month, .day], from: .now)
        return "\(day.year!)年\(day.month!)月\(day.day!)日"
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
