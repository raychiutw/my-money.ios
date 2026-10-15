import XCTest

/// 信用卡詳細頁(#73):帳戶頁的信用卡精簡列點進去，每個欄位一列;結帳日出帳作業、校準未出帳與信用卡扣款還款都在這一頁。
/// 資料來自 MyMoneyTestSupport 的 `SampleAccounts`(不連網路)。
final class CardSettlementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 點信用卡精簡列進入詳細頁：標題是卡名，「卡費」「設定」的每個欄位各一列，toolbar 有「編輯」。
    @MainActor
    func testCardDetailShowsEveryField() throws {
        let app = launchSignedIn()
        openCard("sample-card", named: "iOS 測試信用卡", in: app)

        // 信用卡待繳總額 = 已出帳待繳款 12,000 + 未出帳款 3,500;剩餘額度 = 信用額度 100,000 − 15,500。
        for (label, value) in [
            ("信用卡待繳總額", "$15,500"), ("已出帳待繳款", "$12,000"), ("未出帳款", "$3,500"),
            ("家庭代墊公帳", "$3,000"), ("個人私帳消費", "$12,500"),
            ("信用額度", "$100,000"), ("剩餘額度", "$84,500"), ("結帳日", "每月 15 日"), ("繳款日", "每月 5 日"),
        ] {
            let row = field(label, value: value, in: app)
            for _ in 0..<5 where !row.exists { app.swipeUp() }
            XCTAssertTrue(row.exists, "詳細頁沒有「\(label)」\(value) 這一列")
        }
        XCTAssertTrue(app.navigationBars.buttons["cardDetail.edit"].exists, "詳細頁的 toolbar 沒有「編輯」")
    }

    /// 結帳日出帳作業(上游 ADR 0024):詳細頁的「出帳作業」打開預覽 sheet,確認後顯示後端的訊息;未出帳款轉入已出帳待繳款，
    /// 有結帳日的卡出帳過之後「出帳作業」仍在(可以再檢視這一期)。
    /// 信用卡扣款還款：詳細頁的「繳款」選單選「繳家庭代墊」打開(帶入 3,000),已出帳待繳款從 12,000 變成 9,000。
    @MainActor
    func testRolloverAndPayment() throws {
        let app = launchSignedIn()
        openCard("sample-low-limit-card", named: "iOS 測試小額卡", in: app)

        let rollover = app.buttons["cardDetail.rollover"]
        reveal(rollover, in: app)
        rollover.tap()
        XCTAssertTrue(app.buttons["statementRollover.submit"].waitForExistence(timeout: 3), "沒有打開出帳作業預覽")
        XCTAssertTrue(element(in: app, labelContaining: "加油").waitForExistence(timeout: 3), "預覽沒有列出這一期的明細")
        app.buttons["statementRollover.submit"].tap()
        // 後端訊息的簡化版(in-memory),照原樣顯示。
        XCTAssertTrue(
            element(in: app, labelContaining: "帳單出帳作業完成！本期結算 2 筆消費").waitForExistence(timeout: 5),
            "沒有顯示出帳作業的結果"
        )
        app.buttons["好"].tap()
        XCTAssertTrue(field("未出帳款", value: "$0", in: app).waitForExistence(timeout: 5), "出帳作業後詳細頁的未出帳款沒有更新")
        reveal(rollover, in: app)
        XCTAssertTrue(rollover.exists, "有結帳日的卡出帳過之後，「出帳作業」應該還在(可以再檢視這一期)")

        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        openCard("sample-card", named: "iOS 測試信用卡", in: app)
        let pay = app.buttons["cardDetail.pay"]
        reveal(pay, in: app)
        pay.tap()
        let payShared = app.buttons["繳家庭代墊"]
        XCTAssertTrue(payShared.waitForExistence(timeout: 3), "「繳款」選單裡沒有「繳家庭代墊」")
        payShared.tap()
        let amount = app.textFields["cardPayment.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "「繳款」選單沒有打開信用卡扣款還款")
        XCTAssertEqual(amount.value as? String, "3000", "「繳家庭代墊」沒有帶入家庭公帳的欠款")
        // 歸屬是內嵌選擇列(2 列，點一下就選)，表單裡沒有分段控制(#65、ADR-0004、#90)。
        let form = app.collectionViews.containing(.textField, identifier: "cardPayment.amount").firstMatch
        XCTAssertTrue(form.buttons["個人私帳"].exists, "信用卡扣款還款的歸屬缺少「私帳」這一列")
        XCTAssertTrue(form.buttons["家庭公帳"].isSelected, "「繳家庭代墊」的歸屬不是公帳")
        XCTAssertEqual(form.segmentedControls.count, 0, "信用卡扣款還款的表單裡還有分段控制")
        // 扣款帳戶是空的(上游 ADR 0011、#112):顯示佔位文字，選了扣款銀行之後才另起一列顯示可用餘額。
        let bankRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "扣款帳戶")).firstMatch
        XCTAssertTrue(bankRow.waitForExistence(timeout: 3), "信用卡扣款還款沒有「扣款帳戶」列")
        XCTAssertTrue(bankRow.displayedText.contains("請選擇扣款銀行"), "扣款帳戶沒有顯示佔位文字:\(bankRow.displayedText)")
        XCTAssertFalse(row("可用餘額", value: "50,000 元", in: app).exists, "還沒選扣款帳戶就顯示了可用餘額")
        bankRow.tap()
        let bankOption = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "iOS 測試存款")).firstMatch
        XCTAssertTrue(bankOption.waitForExistence(timeout: 3), "沒有推入扣款帳戶清單頁")
        bankOption.tap()
        XCTAssertTrue(row("可用餘額", value: "50,000 元", in: app).waitForExistence(timeout: 3), "信用卡扣款還款沒有另起一列顯示扣款帳戶的可用餘額")
        // 點金額欄全選後重打一次，直接取代原值(#32)。
        amount.tap()
        amount.typeText("3000")
        XCTAssertEqual(amount.value as? String, "3000")
        app.buttons["cardPayment.submit"].tap()

        XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "還款後信用卡扣款還款沒有關閉")
        let billed = field("已出帳待繳款", value: "$9,000", in: app)
        for _ in 0..<5 where !billed.exists { app.swipeDown() }
        XCTAssertTrue(billed.waitForExistence(timeout: 5), "還款後詳細頁的已出帳待繳款沒有更新")
    }

    /// 出帳預覽的延期試算(上游 ADR 0024):開窗時已延期的 800 不算進本期;再把午餐 1,200 延至下期，摘要就地重算(不呼叫後端);
    /// 關閉不送出、卡上的數字不變;重開後確認，後端依延期的明細重算已出帳待繳款與未出帳款。
    @MainActor
    func testRolloverPreviewDeferralRecomputesLocally() throws {
        let app = launchSignedIn()
        openCard("sample-card", named: "iOS 測試信用卡", in: app)
        let rollover = app.buttons["cardDetail.rollover"]
        reveal(rollover, in: app)
        rollover.tap()

        XCTAssertTrue(row("出帳淨額", value: "1,400 元", in: app).waitForExistence(timeout: 5), "開窗時的出帳淨額不對")
        XCTAssertTrue(row("出帳後已出帳待繳款", value: "13,400 元", in: app).exists)
        XCTAssertTrue(row("出帳後未出帳款", value: "2,100 元", in: app).exists)
        XCTAssertTrue(element(in: app, labelContaining: "含 1 筆上期延入款，已預設納入本期").exists, "沒有提示上期延入款")

        let lunch = app.switches["statementRollover.item.sample-stmt-lunch"]
        XCTAssertTrue(lunch.exists, "預覽沒有午餐那一筆")
        XCTAssertEqual(lunch.value as? String, "0", "午餐開窗時不該延期")
        XCTAssertEqual(app.switches["statementRollover.item.sample-stmt-deferred"].value as? String, "1", "已延期的那筆開關沒有打開")
        flip(lunch)
        XCTAssertTrue(row("出帳淨額", value: "200 元", in: app).waitForExistence(timeout: 3), "延期午餐後出帳淨額沒有重算")
        XCTAssertTrue(row("出帳後已出帳待繳款", value: "12,200 元", in: app).exists)
        XCTAssertTrue(row("出帳後未出帳款", value: "3,300 元", in: app).exists)

        // 關閉:沒有送出，卡上的數字不變。
        app.buttons["關閉"].tap()
        XCTAssertTrue(app.buttons["statementRollover.submit"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(field("已出帳待繳款", value: "$12,000", in: app).exists, "關閉預覽後卡上的已出帳待繳款變了")
        XCTAssertTrue(field("未出帳款", value: "$3,500", in: app).exists, "關閉預覽後卡上的未出帳款變了")

        // 重開:延期不保留，回到開窗時的狀態;再延午餐、確認。
        reveal(rollover, in: app)
        rollover.tap()
        XCTAssertTrue(row("出帳淨額", value: "1,400 元", in: app).waitForExistence(timeout: 5), "重開預覽沒有回到開窗時的狀態")
        flip(app.switches["statementRollover.item.sample-stmt-lunch"])
        app.buttons["statementRollover.submit"].tap()
        XCTAssertTrue(
            element(in: app, labelContaining: "帳單出帳作業完成！本期結算 1 筆消費，淨額 NT$ 200 已轉入已出帳待繳款。（另有 2 筆消費已延至下期）")
                .waitForExistence(timeout: 5),
            "沒有顯示出帳作業的結果"
        )
        app.buttons["好"].tap()
        XCTAssertTrue(field("未出帳款", value: "$3,300", in: app).waitForExistence(timeout: 5), "出帳後的未出帳款不對")
        XCTAssertTrue(field("已出帳待繳款", value: "$12,200", in: app).exists, "出帳後的已出帳待繳款不對")
    }

    /// 開關在列的最右邊:點整列的中央會落在標籤上，改點開關本身所在的右側。
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// 校準未出帳(#48):從詳細頁，先確認(說明重算的期間、會扣掉刷退和還款實際沖到未出帳款的部分),完成後顯示後端的訊息。
    @MainActor
    func testReconcileUnbilled() throws {
        let app = launchSignedIn()
        openCard("sample-card", named: "iOS 測試信用卡", in: app)

        let reconcile = app.buttons["cardDetail.reconcile"]
        reveal(reconcile, in: app)
        reconcile.tap()
        XCTAssertTrue(
            element(in: app, labelContaining: "會重算還沒出帳的消費（過了結帳日、還沒按「出帳作業」的那一期也算在內），加上延至下期的消費").waitForExistence(timeout: 3),
            "確認時沒有說明依結帳區間重算(上游 ADR 0020)"
        )
        app.buttons["校準"].firstMatch.tap()

        XCTAssertTrue(
            element(in: app, labelContaining: "已自動校準「iOS 測試信用卡」未出帳金額為 NT$ 3,500").waitForExistence(timeout: 5),
            "沒有顯示校準的結果"
        )
    }

    /// 帳戶頁的信用卡精簡列(整列是導覽連結)點進詳細頁;導覽列的標題是卡名。
    @MainActor
    private func openCard(_ id: String, named name: String, in app: XCUIApplication) {
        let row = app.buttons["accounts.card.\(id)"]
        _ = row.waitForExistence(timeout: 5)
        reveal(row, in: app)
        XCTAssertTrue(row.exists, "帳戶頁沒有「\(name)」的精簡列")
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 3), "點精簡列沒有進入「\(name)」的詳細頁")
    }

    /// 往上捲到元素完整露出在 tab bar 上面。tab bar 是透明的，底下的元素 `isHittable` 也是 true,點下去卻會點到 tab bar。
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<6 {
            if element.exists, element.isHittable, !tabBar.exists || element.frame.maxY <= tabBar.frame.minY { return }
            app.swipeUp()
        }
    }

    /// 詳細頁的一個欄位(`LabeledContent`):VoiceOver 把標籤和值合成一個元素，例如「信用卡待繳總額、$15,500」。
    @MainActor
    private func field(_ label: String, value: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["\(label)、\(value)"]
    }

    /// 一般列(`AmountRow`):VoiceOver 念標籤，值是金額。
    @MainActor
    private func row(_ label: String, value: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", label, value)).firstMatch
    }

    @MainActor
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// 登入 in-memory 的範例帳號，切到帳戶 tab。
    @MainActor
    private func launchSignedIn() -> XCUIApplication {
        let app = XCUIApplication.launchUITesting(signedIn: true)
        app.tabBars.buttons["帳戶"].tap()
        return app
    }
}
