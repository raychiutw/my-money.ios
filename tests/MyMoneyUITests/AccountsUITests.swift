import XCTest

/// 「帳戶」tab 的瀏覽畫面。資料來自 MyMoneyTestSupport 的 `SampleAccounts`(不連網路)。
///
/// 每一列都合併成一個 accessibility element(VoiceOver 一次念完),所以用 label 的內容找元素。
final class AccountsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 顯示主視覺、現金、活存帳戶與信用卡帳戶三區。每個帳戶是一張卡片(#119);信用卡卡片:名稱、歸屬、
    /// 信用卡待繳總額與繳款日;剩餘額度這些欄位在詳細頁(`CardSettlementUITests`)。
    @MainActor
    func testAccountsTabShowsSummaryAndBothSections() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["帳戶"].tap()

        // 主視覺(#119):淨可用餘額是超大的數字，在最上面;下面是組成比例條，再下面是三格數字磚。
        let available = row("淨可用餘額", value: "21,500 元", in: app)
        XCTAssertTrue(available.waitForExistence(timeout: 5), "沒有淨可用餘額")
        XCTAssertGreaterThan(available.frame.height, 50, "淨可用餘額不是大數字")
        // 範例沒有現金(現金是 0，不畫在比例條上)，活存帳戶 50,000 與信用卡待繳 28,500 共 78,500:64% 與 36%。
        let composition = element(in: app, labelContaining: "資金組成，活存帳戶百分之 64，信用卡待繳百分之 36")
        XCTAssertTrue(composition.exists, "沒有組成比例條")
        XCTAssertLessThan(available.frame.minY, composition.frame.minY, "比例條不在淨可用餘額下面")
        for (label, value) in [("現金總額", "0 元"), ("活存帳戶餘額合計", "50,000 元"), ("信用卡待繳總額", "28,500 元")] {
            let summaryRow = row(label, value: value, in: app)
            XCTAssertTrue(summaryRow.exists, "摘要沒有「\(label) \(value)」這一磚")
            XCTAssertLessThan(composition.frame.minY, summaryRow.frame.minY, "比例條不在「\(label)」上面")
        }
        // 帳戶數在 section 標題，已出帳待繳款和未出帳款在信用卡詳細頁。
        XCTAssertFalse(element(in: app, labelContaining: "個現金").exists, "摘要還有現金的個數")
        XCTAssertFalse(element(in: app, labelContaining: "個活存帳戶").exists, "摘要還有活存帳戶的個數")
        XCTAssertFalse(element(in: app, labelContaining: "已出帳待繳").exists, "摘要還有已出帳待繳款")
        // 摘要和現金區塊在上面，活存帳戶和信用卡要捲下去才在 UI 階層裡。
        let bank = element(in: app, labelContaining: "iOS 測試存款,餘額 50,000 元")
        for _ in 0..<5 where !bank.exists { app.swipeUp() }
        XCTAssertTrue(bank.exists)
        // 信用卡標示公帳或私帳(web 的 bd0507b、上游 ADR 0014)。整列念成一句話，第 2 行只放繳款日(#73)。
        let card = app.buttons["iOS 測試信用卡，個人私帳，信用卡待繳總額 15,500 元，每月 5 日繳款"]
        for _ in 0..<5 where !card.exists { app.swipeUp() }
        XCTAssertTrue(card.exists, "信用卡不是卡片(名稱、私帳、信用卡待繳總額、繳款日)")
        XCTAssertEqual(card.identifier, "accounts.card.sample-card", "信用卡卡片的識別碼不對")
        // 小額卡在畫面下方;List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let lowLimit = app.buttons["iOS 測試小額卡，個人私帳，信用卡待繳總額 13,000 元，每月 20 日繳款"]
        for _ in 0..<5 where !lowLimit.exists { app.swipeUp() }
        XCTAssertTrue(lowLimit.exists, "小額卡不是卡片")
        XCTAssertFalse(element(in: app, labelContaining: "負債性質拆解").exists, "帳戶頁還有負債性質拆解，應該移到詳細頁")
    }

    /// 帳戶檢視範圍是「全部」「公帳」「私帳」(web 的 bd0507b、上游 ADR 0014),在 toolbar 的篩選按鈕(#64):
    /// 點按鈕再選，按鈕的 VoiceOver 值是目前的範圍。範例資料的資產帳戶都是私帳，切到公帳之後，活存帳戶區塊是空的。
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

        filter.tap()
        for option in ["全部", "家庭公帳", "個人私帳"] {
            XCTAssertTrue(app.buttons[option].waitForExistence(timeout: 3), "帳戶檢視範圍選單裡沒有「\(option)」")
        }
        app.buttons["家庭公帳"].tap()
        XCTAssertEqual(filter.value as? String, "家庭公帳", "切換帳戶檢視範圍後篩選按鈕的 VoiceOver 值沒有跟著變")

        // 活存帳戶區塊在統計卡和現金區塊下面，捲下去才在 UI 階層裡。
        let empty = element(in: app, labelContaining: "目前此範圍無活存帳戶")
        _ = empty.waitForExistence(timeout: 2)
        for _ in 0..<5 where !empty.exists { app.swipeUp() }
        XCTAssertTrue(empty.exists, "切到公帳之後，還看得到私帳的活存帳戶")
        XCTAssertFalse(element(in: app, labelContaining: "iOS 測試存款").exists)
    }

    /// 從現金區塊的空狀態新增現金(#43,web 的「目前此範圍無現金」):新增後出現在現金區塊。
    @MainActor
    func testAddCashWallet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "目前此範圍無現金").waitForExistence(timeout: 5))
        // 跟 web 一樣是「建立」(W:Accounts.tsx@f32ff6c:473,#79)。
        XCTAssertEqual(app.buttons["accounts.emptyAdd.cash"].label, "立即建立現金")

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

        XCTAssertTrue(element(in: app, labelContaining: "UI 測試皮夾,現金餘額 800 元").waitForExistence(timeout: 5), "新增後沒有出現在現金區塊")
    }

    /// 新增資產帳戶的類型是內嵌選擇列(3 列，點一下就選)，表單裡沒有分段控制(#65、ADR-0004、#90)。
    /// 從現金切成信用卡之後，出現信用卡的未出帳款欄，餘額欄不見。
    @MainActor
    func testAccountKindIsAnInlineChoice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "活存帳戶餘額合計").waitForExistence(timeout: 5))

        app.buttons["accounts.add"].tap()
        app.buttons["新增現金"].tap()
        let name = app.textFields["accountEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3), "沒有打開新增資產帳戶")
        let form = app.collectionViews.containing(.textField, identifier: "accountEditor.name").firstMatch
        for option in ["現金", "活存帳戶", "信用卡"] {
            XCTAssertTrue(form.buttons[option].exists, "資產帳戶的類型缺少「\(option)」這一列")
        }
        XCTAssertTrue(form.buttons["現金"].isSelected, "從「新增現金」打開，類型不是現金")
        XCTAssertEqual(form.segmentedControls.count, 0, "資產帳戶表單裡還有分段控制")

        form.buttons["信用卡"].tap()
        XCTAssertTrue(form.buttons["信用卡"].isSelected, "點一下信用卡之後沒有選起來")
        XCTAssertTrue(app.textFields["accountEditor.unbilled"].waitForExistence(timeout: 3), "切成信用卡之後沒有未出帳款欄")
        XCTAssertFalse(app.textFields["accountEditor.amount"].exists, "切成信用卡之後還有餘額欄")
    }

    /// 信用卡的結帳日、繳款日(未設定加 1～31 號)推入清單頁，選了自動返回(ADR-0004、#91)。
    @MainActor
    func testStatementDayIsAPushedList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "活存帳戶餘額合計").waitForExistence(timeout: 5))

        app.buttons["accounts.add"].tap()
        app.buttons["新增信用卡"].tap()
        XCTAssertTrue(app.textFields["accountEditor.name"].waitForExistence(timeout: 3), "沒有打開新增信用卡")

        func statementRow() -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "結帳日")).firstMatch
        }
        for _ in 0..<6 where !(statementRow().exists && statementRow().isHittable) { app.swipeUp() }
        XCTAssertTrue(statementRow().exists, "信用卡表單沒有「結帳日」列")
        statementRow().tap()
        let first = app.buttons["每月 1 號"]
        XCTAssertTrue(first.waitForExistence(timeout: 3), "點了結帳日沒有推入日期清單頁")
        XCTAssertTrue(app.buttons["未設定"].exists, "日期清單頁沒有「未設定」")
        first.tap()
        XCTAssertTrue(statementRow().waitForExistence(timeout: 3), "選了日期之後沒有自動返回")
        XCTAssertTrue(statementRow().displayedText.contains("每月 1 號"), "返回之後結帳日不是每月 1 號:\(statementRow().displayedText)")
    }

    /// ATM 提款(#43):活存帳戶轉到現金，顯示後端的訊息，兩邊的餘額都更新。
    @MainActor
    func testATMWithdrawalMovesMoneyIntoWallet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(row("活存帳戶餘額合計", value: "50,000 元", in: app).waitForExistence(timeout: 5))
        app.buttons["accounts.add"].tap()
        app.buttons["新增現金"].tap()
        let name = app.textFields["accountEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 測試皮夾")
        let walletAmount = app.textFields["accountEditor.amount"]
        walletAmount.tap()
        walletAmount.typeText("800")
        app.buttons["accountEditor.save"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "UI 測試皮夾,現金餘額 800 元").waitForExistence(timeout: 5))

        // 轉出與轉入都是空的(上游 ADR 0011、#111):頂端入口不預選;按快捷情境「ATM 提款至皮夾」(使用者主動按的輔助)
        // 才帶入第一個活存帳戶與第一個現金。
        app.buttons["accounts.transfer"].tap()
        let amount = app.textFields["transfer.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開轉帳")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "請選擇轉出帳戶")).firstMatch.exists, "轉出帳戶沒有顯示佔位文字")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "請選擇轉入帳戶")).firstMatch.exists, "轉入帳戶沒有顯示佔位文字")
        XCTAssertFalse(row("可用餘額", value: "50,000 元", in: app).exists, "還沒選轉出帳戶就顯示了可用餘額")
        app.buttons["transfer.atm"].tap()
        XCTAssertTrue(row("可用餘額", value: "50,000 元", in: app).exists, "轉帳沒有另起一列顯示轉出帳戶的可用餘額")
        XCTAssertFalse(element(in: app, labelContaining: "餘額 $").exists, "帳戶選擇列還把餘額塞在選項文字裡")
        amount.tap()
        amount.typeText("500")
        app.buttons["transfer.submit"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "ATM 提款成功 NT$ 500").waitForExistence(timeout: 5), "沒有顯示轉帳的結果")
        app.buttons["好"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "UI 測試皮夾,現金餘額 1,300 元").waitForExistence(timeout: 5), "現金的餘額沒有增加")
        // 活存帳戶區塊在現金區塊下面，捲下去才在 UI 階層裡。
        let bank = element(in: app, labelContaining: "iOS 測試存款,餘額 49,500 元")
        for _ in 0..<5 where !bank.exists { app.swipeUp() }
        XCTAssertTrue(bank.exists, "活存帳戶的餘額沒有減少")
    }

    /// 活存帳戶列往右滑的「轉帳／提款」只帶入轉出，轉入是空的(上游 ADR 0011、#111)。
    @MainActor
    func testBankRowShortcutFillsOnlyTheFromAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()

        let bank = element(in: app, labelContaining: "iOS 測試存款,餘額 50,000 元")
        _ = bank.waitForExistence(timeout: 5)
        for _ in 0..<6 where !(bank.exists && bank.isHittable) { app.swipeUp() }
        XCTAssertTrue(bank.exists, "帳戶頁沒有 iOS 測試存款這一列")
        bank.swipeRight()
        app.buttons["轉帳／提款"].firstMatch.tap()

        XCTAssertTrue(app.textFields["transfer.amount"].waitForExistence(timeout: 3), "沒有打開轉帳")
        let from = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "轉出帳戶")).firstMatch
        let to = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "轉入帳戶")).firstMatch
        XCTAssertTrue(from.displayedText.contains("iOS 測試存款"), "從活存帳戶列進來，轉出沒有帶入這個帳戶:\(from.displayedText)")
        XCTAssertTrue(to.displayedText.contains("請選擇轉入帳戶"), "轉入應該是空的，顯示佔位文字:\(to.displayedText)")
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

    /// 從「+」新增活存帳戶後出現在列表上;往左滑刪除、確認後消失。
    @MainActor
    func testAddThenDeleteBankAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "活存帳戶餘額合計").waitForExistence(timeout: 5))

        app.buttons["accounts.add"].tap()
        app.buttons["新增活存帳戶"].tap()
        let name = app.textFields["accountEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 測試帳戶")
        let amount = app.textFields["accountEditor.amount"]
        amount.tap()
        amount.typeText("1234")
        XCTAssertEqual(amount.value as? String, "1234", "金額欄沒有改成 1234")
        app.buttons["accountEditor.save"].tap()

        // 新帳戶在列表下方(上面有摘要和現金區塊):List 還沒捲到的列不在 UI 階層裡，
        // 先捲到點得到，左滑才滑得出「刪除」。
        let row = element(in: app, labelContaining: "UI 測試帳戶,餘額 1,234 元")
        _ = row.waitForExistence(timeout: 2)
        // 卡片比以前的列高，中心點要離開浮動的 tab bar:在 tab bar 上左滑是切換 tab，不是滑出「刪除」。
        let tabBarTop = app.tabBars.firstMatch.frame.minY
        for _ in 0..<6 where !(row.exists && row.isHittable && row.frame.midY < tabBarTop - 20) { app.swipeUp() }
        XCTAssertTrue(row.exists, "新增後沒有出現在列表上")
        row.swipeLeft()
        app.buttons["刪除"].firstMatch.tap()
        // 左滑的「刪除」只會打開確認對話框;等對話框出現後，再點對話框裡的「刪除」。
        XCTAssertTrue(
            app.staticTexts["確定要刪除帳戶「UI 測試帳戶」嗎？這個帳戶的收支明細也會一併刪除！"].waitForExistence(timeout: 3),
            "沒有先確認就刪除"
        )
        app.buttons["刪除"].firstMatch.tap()

        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "刪除後還在列表上")
    }

    /// 編輯權限防呆(上游 ADR 0013、#133):別人(小美)建立的家庭共同基金，一般成員點不開(不是按鈕)、左滑沒有「刪除」;
    /// 自己的帳戶照舊可以點開。家庭管理員改得了共同基金，所以那一列是按鈕，左滑有「刪除」。
    @MainActor
    func testMemberCannotEditAnothersJointFundButAdminCan() throws {
        for isAdmin in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-uiTestingFamilyEntries", "-resetSession"]
                + (isAdmin ? [] : ["-uiTestingMemberRole"])
            app.launch()
            signIn(app)
            app.tabBars.buttons["帳戶"].tap()
            XCTAssertTrue(element(in: app, labelContaining: "活存帳戶餘額合計").waitForExistence(timeout: 5))

            let mei = element(in: app, labelContaining: "小美的共同基金,餘額 8,000 元,家庭公帳")
            let tabBarTop = app.tabBars.firstMatch.frame.minY
            for _ in 0..<8 where !(mei.exists && mei.isHittable && mei.frame.midY < tabBarTop - 20) { app.swipeUp() }
            XCTAssertTrue(mei.exists, "沒有看到小美建立的家庭共同基金")
            let role = isAdmin ? "家庭管理員" : "一般成員"

            // 角色在登入時問一次，晚一點才到:家庭管理員等「可以點開」出現，一般成員則一直都點不開。
            let meiButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "小美的共同基金")).firstMatch
            if isAdmin {
                XCTAssertTrue(meiButton.waitForExistence(timeout: 5), "\(role):改得了共同基金，那一列應該是按鈕")
            } else {
                XCTAssertFalse(meiButton.waitForExistence(timeout: 2), "\(role):別人建立的共同基金不該點得開")
            }
            let own = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "iOS 測試存款")).firstMatch
            XCTAssertTrue(own.exists, "\(role):自己的帳戶要點得開")

            mei.swipeLeft()
            let delete = app.buttons["刪除"].firstMatch
            if isAdmin {
                XCTAssertTrue(delete.waitForExistence(timeout: 3), "\(role):左滑應該有「刪除」")
            } else {
                XCTAssertFalse(delete.waitForExistence(timeout: 2), "\(role):左滑不該有「刪除」")
            }
            app.terminate()
        }
    }

    /// 公帳範圍的私卡代墊(上游 ADR 0015、#139):小美的個人信用卡替家庭墊了 1,200，公帳範圍看得到(脫敏);
    /// 全部範圍看不到。點進詳細頁:卡費只有家庭代墊，個人帳單與個人消費「隱私遮蔽」，沒有信用額度，也沒有編輯。
    @MainActor
    func testHouseholdScopeShowsMaskedPrivateCardAdvance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-uiTestingMemberRole", "-uiTestingFamilyEntries", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "活存帳戶餘額合計").waitForExistence(timeout: 5))

        // 全部範圍:他人的私卡不在。
        let tabBarTop = app.tabBars.firstMatch.frame.minY
        for _ in 0..<8 where !element(in: app, labelContaining: "iOS 測試信用卡，個人私帳").exists { app.swipeUp() }
        XCTAssertFalse(element(in: app, labelContaining: "小美的信用卡").exists, "全部範圍不該看到他人的私卡")
        for _ in 0..<8 { app.swipeDown() }

        let filter = app.buttons["accounts.scope"]
        filter.tap()
        app.buttons["家庭公帳"].tap()
        XCTAssertEqual(filter.value as? String, "家庭公帳")

        let mei = app.buttons["小美的信用卡，私卡代墊，持卡人 小美，家庭代墊待繳額 1,200 元，每月 25 日繳款"]
        for _ in 0..<8 where !(mei.exists && mei.isHittable && mei.frame.midY < tabBarTop - 20) { app.swipeUp() }
        XCTAssertTrue(mei.exists, "公帳範圍沒有看到小美的私卡代墊")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "iOS 測試信用卡，私卡代墊，信用卡待繳總額")).firstMatch.exists,
            "自己有家庭代墊的私卡在公帳範圍也標私卡代墊"
        )

        mei.tap()
        XCTAssertTrue(app.navigationBars["小美的信用卡"].waitForExistence(timeout: 3), "沒有進入詳細頁")
        for (title, value) in [("家庭公帳代墊待繳總額", "$1,200"), ("個人帳單狀態", "隱私遮蔽"), ("公帳代墊待清償", "$1,200"), ("個人私帳消費", "隱私遮蔽")] {
            // `LabeledContent`:VoiceOver 把標籤和值合成一個元素，例如「家庭公帳代墊待繳總額、$1,200」。
            XCTAssertTrue(app.staticTexts["\(title)、\(value)"].exists, "詳細頁沒有「\(title) \(value)」")
        }
        XCTAssertFalse(app.staticTexts["信用額度"].exists, "他人的信用額度不該揭露")
        XCTAssertFalse(app.staticTexts["剩餘額度"].exists, "他人的剩餘額度不該揭露")
        XCTAssertFalse(app.buttons["cardDetail.edit"].exists, "不能編輯他人的卡")
        XCTAssertFalse(app.buttons["cardDetail.reconcile"].exists, "不能校準他人的卡")
    }

    /// 非持卡人繳他人私卡的家庭代墊(上游 ADR 0015、#140):詳細頁只有「繳家庭代墊」(沒有繳款選單、出帳作業、校準);
    /// 還款表單歸屬固定公帳、沒有私帳可選、金額帶入家庭代墊待繳額;繳清之後這張卡就不在公帳範圍了(後端只回有家庭代墊欠款的私卡)。
    @MainActor
    func testNonHolderPaysSharedDebtOfAnothersPrivateCard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-uiTestingMemberRole", "-uiTestingFamilyEntries", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "活存帳戶餘額合計").waitForExistence(timeout: 5))
        let filter = app.buttons["accounts.scope"]
        filter.tap()
        app.buttons["家庭公帳"].tap()

        let mei = app.buttons["小美的信用卡，私卡代墊，持卡人 小美，家庭代墊待繳額 1,200 元，每月 25 日繳款"]
        let tabBarTop = app.tabBars.firstMatch.frame.minY
        for _ in 0..<8 where !(mei.exists && mei.isHittable && mei.frame.midY < tabBarTop - 20) { app.swipeUp() }
        mei.tap()
        let pay = app.buttons["cardDetail.paySharedDebt"]
        for _ in 0..<5 where !pay.exists { app.swipeUp() }
        XCTAssertTrue(pay.exists, "他人私卡的詳細頁沒有「繳家庭代墊」")
        XCTAssertFalse(app.buttons["cardDetail.pay"].exists, "他人私卡不該有繳款選單(繳個人私帳、全額結清)")
        XCTAssertFalse(app.buttons["cardDetail.rollover"].exists, "他人私卡不該有出帳作業")
        XCTAssertFalse(app.buttons["cardDetail.reconcile"].exists, "他人私卡不該有校準")

        pay.tap()
        let amount = app.textFields["cardPayment.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開信用卡扣款還款")
        XCTAssertEqual(amount.value as? String, "1200", "金額沒有帶入家庭代墊待繳額")
        XCTAssertTrue(app.staticTexts["cardPayment.fixedShared"].exists || element(in: app, labelContaining: "僅限自家庭共同帳戶沖抵他人私卡之家庭代墊款").exists, "沒有說明歸屬固定公帳")
        let form = app.collectionViews.containing(.textField, identifier: "cardPayment.amount").firstMatch
        XCTAssertFalse(form.buttons["個人私帳"].exists, "他人私卡的還款不該有私帳可選")

        let bankRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "扣款帳戶")).firstMatch
        bankRow.tap()
        // 公帳範圍的扣款帳戶只有家庭共同基金。
        let bankOption = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "小美的共同基金")).firstMatch
        XCTAssertTrue(bankOption.waitForExistence(timeout: 3), "沒有推入扣款帳戶清單頁，或清單裡沒有家庭共同基金")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "iOS 測試存款")).firstMatch.exists, "公帳範圍的扣款帳戶不該有私帳的銀行")
        bankOption.tap()
        app.buttons["cardPayment.submit"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5), "還款後信用卡扣款還款沒有關閉")

        // 家庭代墊繳清:這張卡不再有家庭代墊欠款，公帳範圍看不到它，詳細頁自動返回。
        XCTAssertTrue(mei.waitForNonExistence(timeout: 8), "繳清之後小美的卡還在公帳範圍")
    }

    /// 公帳範圍的「家庭公帳待報銷代墊款」橫幅(上游 ADR 0015、#141):各成員待報銷加總(範例是 250 + 600)，
    /// 「前往家庭」切到家庭 tab;全部範圍沒有橫幅。
    @MainActor
    func testPendingAdvancesBannerAppearsInHouseholdScopeAndOpensFamily() throws {
        try assertPendingAdvancesBanner(contentSize: nil)
    }

    @MainActor
    func testPendingAdvancesBannerFitsAtXXL() throws {
        try assertPendingAdvancesBanner(contentSize: "UICTContentSizeCategoryXXL")
    }

    @MainActor
    private func assertPendingAdvancesBanner(contentSize: String?) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-resetSession"]
            + (contentSize.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "活存帳戶餘額合計").waitForExistence(timeout: 5))
        XCTAssertFalse(element(in: app, labelContaining: "家庭公帳待報銷代墊款").exists, "全部範圍不該有待報銷橫幅")

        let filter = app.buttons["accounts.scope"]
        filter.tap()
        app.buttons["家庭公帳"].tap()
        let banner = element(in: app, labelContaining: "家庭公帳待報銷代墊款 $850")
        XCTAssertTrue(banner.waitForExistence(timeout: 5), "公帳範圍沒有待報銷橫幅")
        let open = app.buttons["accounts.pendingAdvances.open"]
        XCTAssertTrue(open.exists && open.isHittable, "橫幅沒有可點的「前往家庭」")
        XCTAssertLessThanOrEqual(banner.frame.maxX, app.frame.maxX + 1, "橫幅超出螢幕寬度")
        XCTAssertGreaterThanOrEqual(open.frame.minY, banner.frame.maxY - 1, "按鈕沒有在橫幅文字下面")

        open.tap()
        XCTAssertTrue(app.buttons["household.leave"].waitForExistence(timeout: 5) || element(in: app, labelContaining: "我的角色").waitForExistence(timeout: 5), "「前往家庭」沒有切到家庭 tab")

        // 切回帳戶頁、再切到全部:橫幅不在。
        app.tabBars.buttons["帳戶"].tap()
        filter.tap()
        app.buttons["全部"].tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5), "全部範圍還有待報銷橫幅")
    }

    /// 工具列只有檢視範圍、新增資產帳戶、頭像三顆;「ATM 提款／轉帳」是摘要下面的膠囊按鈕(ADR-0004、#87、#119)。
    @MainActor
    func testToolbarHasThreeButtonsAndTransferIsTheLastSummaryRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(app.buttons["accounts.scope"].waitForExistence(timeout: 5), "沒有檢視範圍按鈕")
        let toolbar = app.navigationBars.firstMatch
        for id in ["accounts.scope", "accounts.add", "toolbar.me"] {
            XCTAssertTrue(toolbar.buttons[id].exists, "工具列缺少 \(id)")
        }
        // 選單型的 toolbar 按鈕(檢視範圍、新增資產帳戶)旁邊，系統會多帶一個沒有名字的按鈕;只數有名字的。
        let named = toolbar.buttons.allElementsBoundByIndex.filter { !$0.identifier.isEmpty || !$0.label.isEmpty }
        XCTAssertEqual(named.count, 3, "工具列不是三顆按鈕:\(toolbar.buttonSummary)")
        XCTAssertFalse(toolbar.buttons["accounts.transfer"].exists, "ATM 提款／轉帳還在工具列")

        let transfer = app.buttons["accounts.transfer"]
        XCTAssertTrue(transfer.waitForExistence(timeout: 3), "摘要下面沒有「ATM 提款／轉帳」")
        XCTAssertEqual(transfer.label, "ATM 提款／轉帳")
        let cardDebt = element(in: app, labelContaining: "信用卡待繳總額")
        XCTAssertTrue(cardDebt.exists)
        XCTAssertGreaterThan(transfer.frame.minY, cardDebt.frame.minY, "「ATM 提款／轉帳」不在數字磚下面")
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
