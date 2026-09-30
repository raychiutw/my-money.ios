import XCTest

/// 「帳戶」tab 的瀏覽畫面。資料來自 MyMoneyTestSupport 的 `SampleAccounts`(不連網路)。
///
/// 每一列都合併成一個 accessibility element(VoiceOver 一次念完),所以用 label 的內容找元素。
final class AccountsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 顯示摘要、現金錢包、銀行存款帳戶與信用卡帳戶三區。信用卡是精簡列(#73):名稱、歸屬、信用卡待繳總額，
    /// 第 2 行只有繳款日;剩餘額度這些欄位在詳細頁(`CardSettlementUITests`)。
    @MainActor
    func testAccountsTabShowsSummaryAndBothSections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["帳戶"].tap()

        // 摘要(#75):淨可用餘額是主數字，在最上面;下面是它的組成，一項一列(`LabeledContent`)。
        let available = element(in: app, labelContaining: "淨可用餘額 21,500 元")
        XCTAssertTrue(available.waitForExistence(timeout: 5), "沒有淨可用餘額")
        for (label, value) in [("現金錢包總額", "0 元"), ("銀行存款帳戶餘額合計", "50,000 元"), ("信用卡待繳總額", "28,500 元")] {
            let summaryRow = row(label, value: value, in: app)
            XCTAssertTrue(summaryRow.exists, "摘要沒有「\(label) \(value)」這一列")
            XCTAssertLessThan(available.frame.minY, summaryRow.frame.minY, "淨可用餘額不在「\(label)」上面")
        }
        // 帳戶數在 section 標題，已出帳待繳款和未出帳款在信用卡詳細頁。
        XCTAssertFalse(element(in: app, labelContaining: "個現金錢包").exists, "摘要還有現金錢包的個數")
        XCTAssertFalse(element(in: app, labelContaining: "個銀行存款帳戶").exists, "摘要還有銀行存款帳戶的個數")
        XCTAssertFalse(element(in: app, labelContaining: "已出帳待繳").exists, "摘要還有已出帳待繳款")
        // 摘要和現金錢包區塊在上面，銀行存款帳戶和信用卡要捲下去才在 UI 階層裡。
        let bank = element(in: app, labelContaining: "iOS 測試存款,餘額 50,000 元")
        for _ in 0..<5 where !bank.exists { app.swipeUp() }
        XCTAssertTrue(bank.exists)
        // 信用卡標示家庭信用卡或個人卡(web 的 bd0507b)。整列念成一句話，第 2 行只放繳款日(#73)。
        let card = app.buttons["iOS 測試信用卡，個人卡，信用卡待繳總額 15,500 元，每月 5 日繳款"]
        for _ in 0..<5 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.exists, "信用卡不是精簡列(名稱、個人卡、信用卡待繳總額、繳款日)")
        XCTAssertEqual(card.identifier, "accounts.card.sample-card", "信用卡精簡列不是導覽連結")
        // 小額卡在畫面下方;List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let lowLimit = app.buttons["iOS 測試小額卡，個人卡，信用卡待繳總額 13,000 元，每月 20 日繳款"]
        for _ in 0..<5 where !lowLimit.exists { app.swipeUp() }
        XCTAssertTrue(lowLimit.exists, "小額卡不是精簡列")
        XCTAssertFalse(element(in: app, labelContaining: "負債性質拆解").exists, "帳戶頁還有負債性質拆解，應該移到詳細頁")
    }

    /// 帳戶檢視範圍是「全部」「家庭共同基金」「個人私帳」(web 的 bd0507b),在 toolbar 的篩選按鈕(#64):
    /// 點按鈕再選，導覽列副標題顯示目前的範圍。範例資料的資產帳戶都是個人私帳，切到家庭共同基金之後，銀行存款帳戶區塊是空的。
    @MainActor
    func testJointFundScopeHidesPersonalAccounts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()

        let filter = app.buttons["accounts.scope"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "toolbar 沒有帳戶檢視範圍的篩選按鈕")
        XCTAssertEqual(filter.label, "帳戶檢視範圍", "篩選按鈕的 VoiceOver 標籤不是「帳戶檢視範圍」")
        XCTAssertEqual(filter.value as? String, "全部", "篩選按鈕的 VoiceOver 值不是目前的帳戶檢視範圍")
        XCTAssertTrue(subtitle("全部", in: app).waitForExistence(timeout: 3), "導覽列副標題沒有顯示目前的帳戶檢視範圍")

        filter.tap()
        for option in ["全部", "家庭共同基金", "個人私帳"] {
            XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 3), "帳戶檢視範圍選單裡沒有「\(option)」")
        }
        app.buttons["家庭共同基金"].tap()
        XCTAssertTrue(subtitle("家庭共同基金", in: app).waitForExistence(timeout: 3), "切換帳戶檢視範圍後導覽列副標題沒有跟著變")
        XCTAssertEqual(filter.value as? String, "家庭共同基金", "切換帳戶檢視範圍後篩選按鈕的 VoiceOver 值沒有跟著變")

        // 銀行存款帳戶區塊在統計卡和現金錢包區塊下面，捲下去才在 UI 階層裡。
        let empty = element(in: app, labelContaining: "目前此範圍無銀行存款帳戶")
        _ = empty.waitForExistence(timeout: 2)
        for _ in 0..<5 where !empty.exists { app.swipeUp() }
        XCTAssertTrue(empty.exists, "切到家庭共同基金之後，還看得到個人私帳的銀行存款帳戶")
        XCTAssertFalse(element(in: app, labelContaining: "iOS 測試存款").exists)
    }

    /// 從現金錢包區塊的空狀態新增現金錢包(#43,web 的「目前此範圍無現金錢包」):新增後出現在現金錢包區塊。
    @MainActor
    func testAddCashWallet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "目前此範圍無現金錢包").waitForExistence(timeout: 5))
        // 跟 web 一樣是「建立」(W:Accounts.tsx@f32ff6c:473,#79)。
        XCTAssertEqual(app.buttons["accounts.emptyAdd.cash"].label, "立即建立現金錢包")

        app.buttons["accounts.emptyAdd.cash"].tap()
        let name = app.textFields["accountEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["名稱"].exists, "資產帳戶表單的名稱欄沒有看得見的標籤")
        name.tap()
        name.typeText("UI 測試皮夾")
        let amount = app.textFields["accountEditor.amount"]
        amount.tap()
        amount.typeText("800")
        app.buttons["accountEditor.save"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "UI 測試皮夾,現金錢包餘額 800 元").waitForExistence(timeout: 5), "新增後沒有出現在現金錢包區塊")
    }

    /// 新增資產帳戶的類型是表單裡一般的選擇列，表單裡沒有分段控制(#65)。
    /// 從現金錢包切成信用卡之後，出現信用卡的未出帳款欄，餘額欄不見。
    @MainActor
    func testAccountKindIsAPickerRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "銀行存款帳戶餘額合計").waitForExistence(timeout: 5))

        app.buttons["accounts.add"].tap()
        app.buttons["新增現金錢包"].tap()
        let name = app.textFields["accountEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3), "沒有打開新增資產帳戶")
        // 選單樣式的 `Picker` 沒有 accessibility value,值是選擇列裡唯一的文字。
        let kind = app.buttons["accountEditor.kind"]
        XCTAssertTrue(kind.exists, "資產帳戶的類型不是表單選擇列")
        XCTAssertEqual(kind.staticTexts.firstMatch.label, "現金錢包", "從「新增現金錢包」打開，類型不是現金錢包")
        let form = app.collectionViews.containing(.textField, identifier: "accountEditor.name").firstMatch
        XCTAssertEqual(form.segmentedControls.count, 0, "資產帳戶表單裡還有分段控制")

        kind.tap()
        let creditCard = app.cells.children(matching: .button)["信用卡"]
        XCTAssertTrue(creditCard.waitForExistence(timeout: 3), "類型選單裡沒有「信用卡」")
        creditCard.tap()
        XCTAssertTrue(app.textFields["accountEditor.unbilled"].waitForExistence(timeout: 3), "切成信用卡之後沒有未出帳款欄")
        XCTAssertFalse(app.textFields["accountEditor.amount"].exists, "切成信用卡之後還有餘額欄")
    }

    /// ATM 提款(#43):銀行存款帳戶轉到現金錢包，顯示後端的訊息，兩邊的餘額都更新。
    @MainActor
    func testATMWithdrawalMovesMoneyIntoWallet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(row("銀行存款帳戶餘額合計", value: "50,000 元", in: app).waitForExistence(timeout: 5))
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
        XCTAssertTrue(element(in: app, labelContaining: "UI 測試皮夾,現金錢包餘額 800 元").waitForExistence(timeout: 5))

        // 預設轉出是第一個銀行存款帳戶、轉入是第一個現金錢包。
        app.buttons["accounts.transfer"].tap()
        let amount = app.textFields["transfer.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開轉帳")
        XCTAssertTrue(row("可用餘額", value: "50,000 元", in: app).exists, "轉帳沒有另起一列顯示轉出帳戶的可用餘額")
        XCTAssertFalse(element(in: app, labelContaining: "餘額 $").exists, "帳戶選擇列還把餘額塞在選項文字裡")
        amount.tap()
        amount.typeText("500")
        app.buttons["transfer.submit"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "ATM 提款成功 NT$ 500").waitForExistence(timeout: 5), "沒有顯示轉帳的結果")
        app.buttons["好"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "UI 測試皮夾,現金錢包餘額 1,300 元").waitForExistence(timeout: 5), "現金錢包的餘額沒有增加")
        // 銀行存款帳戶區塊在現金錢包區塊下面，捲下去才在 UI 階層裡。
        let bank = element(in: app, labelContaining: "iOS 測試存款,餘額 49,500 元")
        for _ in 0..<5 where !bank.exists { app.swipeUp() }
        XCTAssertTrue(bank.exists, "銀行存款帳戶的餘額沒有減少")
    }

    /// 轉帳：焦點在備註欄時，按鍵盤上的「完成」會收起鍵盤(#61)。
    @MainActor
    func testDoneOnTransferNoteDismissesKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()

        app.buttons["accounts.transfer"].tap()
        let note = app.textFields["transfer.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "沒有打開轉帳")
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "點備註欄後沒有出現鍵盤")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "備註欄按「完成」後，鍵盤沒有收起")
    }

    /// 從「+」新增銀行存款帳戶後出現在列表上;往左滑刪除、確認後消失。
    @MainActor
    func testAddThenDeleteBankAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "銀行存款帳戶餘額合計").waitForExistence(timeout: 5))

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

        // 新帳戶在列表下方(上面有摘要和現金錢包區塊):List 還沒捲到的列不在 UI 階層裡，
        // 先捲到點得到，左滑才滑得出「刪除」。
        let row = element(in: app, labelContaining: "UI 測試帳戶,餘額 1,234 元")
        _ = row.waitForExistence(timeout: 2)
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.exists, "新增後沒有出現在列表上")
        row.swipeLeft()
        app.buttons["刪除"].firstMatch.tap()
        // 左滑的「刪除」只會打開確認對話框;等對話框出現後，再點對話框裡的「刪除」。
        XCTAssertTrue(
            app.staticTexts["確定要刪除帳戶「UI 測試帳戶」嗎？這個帳戶的交易記錄也會一併刪除！"].waitForExistence(timeout: 3),
            "沒有先確認就刪除"
        )
        app.buttons["刪除"].firstMatch.tap()

        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "刪除後還在列表上")
    }

    /// 導覽列副標題(`navigationSubtitle`)。
    @MainActor
    private func subtitle(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts[text]
    }

    /// 摘要的一般列(`AmountRow`):VoiceOver 念標籤，值是金額，例如標籤「信用卡待繳總額」、值「28,500 元」。
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
