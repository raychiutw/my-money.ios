import XCTest

/// 「帳戶」tab 的瀏覽畫面。資料來自 MyMoneyTestSupport 的 `SampleAccounts`(不連網路)。
///
/// 每一列都合併成一個 accessibility element(VoiceOver 一次念完),所以用 label 的內容找元素。
final class AccountsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 顯示三張統計卡、銀行存款帳戶與信用卡帳戶兩區，以及剩餘額度不足的警示。
    @MainActor
    func testAccountsTabShowsSummaryAndBothSections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["帳戶"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "iOS 測試存款,餘額 50,000 元").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, labelContaining: "銀行存款帳戶餘額合計 50,000 元").exists)
        XCTAssertTrue(element(in: app, labelContaining: "待繳卡費總額 28,500 元").exists)
        XCTAssertTrue(element(in: app, labelContaining: "淨可用資產 21,500 元").exists)
        // 統計卡和現金錢包區塊在上面，信用卡要捲下去才在 UI 階層裡。
        let card = element(in: app, labelContaining: "iOS 測試信用卡")
        for _ in 0..<5 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.exists)
        // 小額卡在畫面下方(每張信用卡下面還有欠款公私拆解那一列);List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let lowCredit = element(in: app, labelContaining: "額度不足")
        for _ in 0..<5 where !lowCredit.exists { app.swipeUp() }
        XCTAssertTrue(lowCredit.exists, "小額卡沒有顯示剩餘額度不足的警示")
    }

    /// 從「+」新增現金錢包(#43):出現在現金錢包區塊，現金錢包總額也更新。
    @MainActor
    func testAddCashWallet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "尚未新增現金錢包").waitForExistence(timeout: 5))

        app.buttons["accounts.add"].tap()
        app.buttons["新增現金錢包"].tap()
        let name = app.textFields["accountEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 測試皮夾")
        let amount = app.textFields["accountEditor.amount"]
        amount.tap()
        amount.typeText("800")
        app.buttons["accountEditor.save"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "UI 測試皮夾,現金餘額 800 元").waitForExistence(timeout: 5), "新增後沒有出現在現金錢包區塊")
    }

    /// ATM 提款(#43):銀行存款帳戶轉到現金錢包，顯示後端的訊息，兩邊的餘額都更新。
    @MainActor
    func testATMWithdrawalMovesMoneyIntoWallet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "iOS 測試存款,餘額 50,000 元").waitForExistence(timeout: 5))
        app.buttons["accounts.add"].tap()
        app.buttons["新增現金錢包"].tap()
        let name = app.textFields["accountEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 測試皮夾")
        let walletAmount = app.textFields["accountEditor.amount"]
        walletAmount.tap()
        walletAmount.typeText("800")
        app.buttons["accountEditor.save"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "UI 測試皮夾,現金餘額 800 元").waitForExistence(timeout: 5))

        // 預設轉出是第一個銀行存款帳戶、轉入是第一個現金錢包。
        app.buttons["accounts.transfer"].tap()
        let amount = app.textFields["transfer.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開轉帳")
        amount.tap()
        amount.typeText("500")
        app.buttons["transfer.submit"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "ATM 提款成功 NT$ 500").waitForExistence(timeout: 5), "沒有顯示轉帳的結果")
        app.buttons["好"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "UI 測試皮夾,現金餘額 1,300 元").waitForExistence(timeout: 5), "現金錢包的餘額沒有增加")
        // 銀行存款帳戶區塊在現金錢包區塊下面，捲下去才在 UI 階層裡。
        let bank = element(in: app, labelContaining: "iOS 測試存款,餘額 49,500 元")
        for _ in 0..<5 where !bank.exists { app.swipeUp() }
        XCTAssertTrue(bank.exists, "銀行存款帳戶的餘額沒有減少")
    }

    /// 從「+」新增銀行存款帳戶後出現在列表上;往左滑刪除、確認後消失。
    @MainActor
    func testAddThenDeleteBankAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "iOS 測試存款").waitForExistence(timeout: 5))

        app.buttons["accounts.add"].tap()
        app.buttons["新增銀行存款帳戶"].tap()
        let name = app.textFields["accountEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 測試帳戶")
        let amount = app.textFields["accountEditor.amount"]
        amount.tap()
        amount.typeText("1234")
        XCTAssertEqual(amount.value as? String, "1234", "金額欄沒有改成 1234")
        app.buttons["accountEditor.save"].tap()

        // 新帳戶在列表下方(上面有範圍切換、四張統計卡和現金錢包區塊):List 還沒捲到的列不在 UI 階層裡，
        // 先捲到點得到，左滑才滑得出「刪除」。
        let row = element(in: app, labelContaining: "UI 測試帳戶,餘額 1,234 元")
        _ = row.waitForExistence(timeout: 2)
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.exists, "新增後沒有出現在列表上")
        row.swipeLeft()
        app.buttons["刪除"].firstMatch.tap()
        // 左滑的「刪除」只會打開確認對話框;等對話框出現後，再點對話框裡的「刪除」。
        XCTAssertTrue(
            app.staticTexts["確定要刪除帳戶「UI 測試帳戶」嗎？這個帳戶的交易紀錄也會一併刪除！"].waitForExistence(timeout: 3),
            "沒有先確認就刪除"
        )
        app.buttons["刪除"].firstMatch.tap()

        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "刪除後還在列表上")
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
