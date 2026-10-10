import XCTest

/// 家庭 tab。資料來自 MyMoneyTestSupport 的 `InMemoryHouseholdRepository`(一開始沒有家庭，不連網路)。
final class HouseholdUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 建立家庭 → 我是家庭管理員 → 數字優先的主視覺(#121):超大的分攤建議並標明誰轉給誰、各成員代墊長條圖、
    /// 我的累計代墊／已報銷／待報銷 → 邀請(複製後顯示「已複製」)→ 離開(先確認)→ 回到建立的畫面。
    @MainActor
    func testCreateInviteAndLeave() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["家庭"].tap()
        let name = app.textFields["household.createName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "沒有看到建立家庭")
        XCTAssertTrue(app.staticTexts["名稱"].exists, "家庭名稱欄沒有看得見的標籤")
        XCTAssertTrue(app.staticTexts["邀請碼"].exists, "邀請碼欄沒有看得見的標籤")
        XCTAssertFalse(app.buttons["household.create"].isEnabled, "名稱還沒填就能建立")
        name.tap()
        name.typeText("我們家")
        app.buttons["household.create"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "我的角色：家庭管理員").waitForExistence(timeout: 5), "建立後沒有顯示家庭")

        // 範例本月的公帳代墊:小明 6,000、小美 4,000，平均 5,000，小美該轉 1,000 給小明。
        let settlement = element(in: app, labelContaining: "分攤建議,平分後每人應負擔 5,000 元,小美 轉 1,000 元 給 小明")
        XCTAssertTrue(settlement.exists, "沒有分攤建議")
        XCTAssertGreaterThan(settlement.frame.height, 50, "分攤建議不是大數字")
        XCTAssertTrue(element(in: app, labelContaining: "本月各成員公帳代墊，平均 5,000 元").exists, "沒有各成員代墊的長條圖")
        // 我的數字磚:登入的範例帳號小明墊付 250，還沒報銷。
        for (label, value) in [("我的累計公帳墊付", "250 元"), ("我的已獲撥款報銷", "0 元"), ("我的待報銷", "250 元")] {
            let tile = row(label, value: value, in: app)
            XCTAssertTrue(tile.exists, "沒有「\(label) \(value)」這一磚")
            XCTAssertGreaterThan(tile.frame.minY, settlement.frame.maxY - 1, "「\(label)」不在分攤建議下面")
        }

        // 邀請與離開降到最下面，List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let invite = app.buttons["household.invite"]
        for _ in 0..<8 where !(invite.exists && invite.isHittable) { app.swipeUp() }
        invite.tap()
        XCTAssertTrue(app.staticTexts["household.invitationCode"].waitForExistence(timeout: 3), "沒有顯示邀請碼")
        app.buttons["household.copy"].tap()
        XCTAssertTrue(app.buttons["已複製"].waitForExistence(timeout: 2), "複製後沒有顯示「已複製」")
        app.buttons["完成"].tap()

        // 「離開家庭」在「邀請家庭成員」下面，同樣在最下面。
        let leave = app.buttons["household.leave"]
        for _ in 0..<5 where !(leave.exists && leave.isHittable) { app.swipeUp() }
        leave.tap()
        XCTAssertTrue(
            app.staticTexts["確定要退出「我們家」嗎？退出後將無法查看這個家庭的家庭公帳。"].waitForExistence(timeout: 3),
            "沒有先確認就離開"
        )
        app.buttons["離開"].firstMatch.tap()
        XCTAssertTrue(app.textFields["household.createName"].waitForExistence(timeout: 5), "離開後沒有回到建立的畫面")
    }

    /// 一般成員視角(上游 ADR 0013，#132):範例帳號是一般成員、小美是家庭管理員。沒有邀請入口;
    /// 撥款報銷只有自己的代墊款，小美的代墊卡片沒有入口(後端會回 403)。
    @MainActor
    func testMemberHasNoInviteAndOnlyOwnReimbursement() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-uiTestingMemberRole", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["家庭"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "我的角色：一般成員").waitForExistence(timeout: 5), "沒有顯示一般成員的角色")

        // 捲到最底:離開在、邀請不在;小美的區塊(家庭管理員)看得到，但沒有報銷入口。
        let leave = app.buttons["household.leave"]
        for _ in 0..<8 where !(leave.exists && leave.isHittable) { app.swipeUp() }
        XCTAssertTrue(leave.isHittable, "沒有捲到最底")
        XCTAssertFalse(app.buttons["household.invite"].exists, "一般成員不該看到邀請入口")
        XCTAssertTrue(element(in: app, labelContaining: "小美,有待請款代墊").exists, "沒有看到小美的代墊卡片")
        XCTAssertTrue(element(in: app, labelContaining: "家庭管理員").exists, "小美的身分不是家庭管理員")
        XCTAssertFalse(app.buttons["household.reimburse.sample-mei"].exists, "一般成員不該能替小美的代墊款撥款")

        let reimburseMine = app.buttons["household.reimburse.in-memory-member-1"]
        for _ in 0..<8 where !reimburseMine.exists { app.swipeDown() }
        XCTAssertTrue(reimburseMine.exists, "自己的代墊款沒有報銷入口")
    }

    /// 替其他家庭成員撥款報銷(#47):範例帳號建立家庭後，小明和小美都有待報銷
    /// (InMemoryHouseholdRepository.myPendingAdvance、meiPendingAdvance),從共同基金撥給小美的可收款帳戶。
    @MainActor
    func testReimburseAnotherMembersAdvance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        // 先建立家庭共同基金(撥款帳戶)。
        app.tabBars.buttons["帳戶"].tap()
        app.buttons["accounts.add"].tap()
        app.buttons["新增活存帳戶"].tap()
        let fundName = app.textFields["accountEditor.name"]
        XCTAssertTrue(fundName.waitForExistence(timeout: 3))
        fundName.tap()
        fundName.typeText("家庭共同基金")
        let fundAmount = app.textFields["accountEditor.amount"]
        fundAmount.tap()
        fundAmount.typeText("5000")
        // 歸屬選「公帳」(所有類型都一樣，跟 web 一樣;上游 ADR 0014 起叫公帳)。歸屬是內嵌選擇列，只在編輯表單裡找這一列。
        let form = app.collectionViews.containing(.textField, identifier: "accountEditor.name").firstMatch
        let jointFund = form.buttons["家庭公帳"]
        XCTAssertTrue(jointFund.waitForExistence(timeout: 3), "歸屬沒有「公帳」這個選項")
        jointFund.tap()
        app.buttons["accountEditor.save"].tap()

        app.tabBars.buttons["總覽"].tap()
        app.tabBars.buttons["家庭"].tap()
        let name = app.textFields["household.createName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("我們家")
        app.buttons["household.create"].tap()

        // 成員在大數字、長條圖與數字磚下面，List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let mine = element(in: app, labelContaining: "小明,有待請款代墊")
        for _ in 0..<8 where !mine.exists { app.swipeUp() }
        XCTAssertTrue(mine.exists, "沒有顯示我的代墊款")
        let reimburseMine = app.buttons["household.reimburse.in-memory-member-1"]
        for _ in 0..<8 where !reimburseMine.exists { app.swipeUp() }
        XCTAssertTrue(reimburseMine.exists, "自己的代墊款沒有報銷入口")
        let reimburseMei = app.buttons["household.reimburse.sample-mei"]
        for _ in 0..<5 where !reimburseMei.isHittable { app.swipeUp() }
        reimburseMei.tap()
        let submit = app.buttons["reimbursement.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 3), "沒有打開撥款報銷")
        // 帳戶選擇列只顯示名稱，值在 value 或子元素裡(推入清單頁的選擇列，ADR-0004、#88)。
        let receiving = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "收款帳戶")).firstMatch
        let funding = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "撥款公帳")).firstMatch
        XCTAssertTrue(receiving.exists, "撥款報銷沒有「收款帳戶」列")
        // 撥款帳戶與收款帳戶都是空的(上游 ADR 0011、#113):顯示佔位文字;選了撥款帳戶之後才顯示可用餘額。
        XCTAssertTrue(funding.displayedText.contains("請選擇家庭共同基金帳戶"), "撥款帳戶沒有顯示佔位文字:\(funding.displayedText)")
        XCTAssertTrue(receiving.displayedText.contains("請選擇收款個人帳戶"), "收款帳戶沒有顯示佔位文字:\(receiving.displayedText)")
        XCTAssertFalse(row("可用餘額", value: "5,000 元", in: app).exists, "還沒選撥款帳戶就顯示了可用餘額")
        // 沒選就送出:提示缺哪一個，不送出。
        submit.tap()
        XCTAssertTrue(element(in: app, labelContaining: "請選擇家庭共同基金帳戶").waitForExistence(timeout: 3), "沒選撥款帳戶就送出，沒有提示")
        XCTAssertTrue(submit.exists, "沒選撥款帳戶就送出，撥款報銷被關掉了")

        funding.tap()
        let fund = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "家庭共同基金")).firstMatch
        XCTAssertTrue(fund.waitForExistence(timeout: 3), "沒有推入撥款帳戶清單頁")
        fund.tap()
        receiving.tap()
        let meiBank = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "小美薪轉")).firstMatch
        XCTAssertTrue(meiBank.waitForExistence(timeout: 3), "沒有推入收款帳戶清單頁")
        meiBank.tap()
        XCTAssertTrue(receiving.displayedText.contains("小美薪轉"), "收款帳戶不是小美的可收款帳戶:\(receiving.displayedText)")
        XCTAssertFalse(element(in: app, labelContaining: "(活存帳戶)").exists, "帳戶選擇列的值還帶著類型")
        XCTAssertTrue(row("可用餘額", value: "5,000 元", in: app).waitForExistence(timeout: 3), "撥款報銷沒有另起一列顯示撥款帳戶的可用餘額")
        submit.tap()

        XCTAssertTrue(element(in: app, labelContaining: "成功從共同基金撥款報銷 NT$ 600 給 小美").waitForExistence(timeout: 5), "沒有顯示撥款報銷的結果")
        app.buttons["好"].tap()
        let settled = element(in: app, labelContaining: "小美,已全數結清")
        for _ in 0..<5 where !settled.exists { app.swipeUp() }
        XCTAssertTrue(settled.exists, "報銷後沒有結清")
    }

    /// 撥款報銷：焦點在備註欄時，按鍵盤上的「完成」會收起鍵盤(#61)。
    /// 範例帳號建立家庭後，自己就有待報銷(InMemoryHouseholdRepository.myPendingAdvance)。
    @MainActor
    func testDoneOnReimbursementNoteDismissesKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["家庭"].tap()
        let name = app.textFields["household.createName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("我們家")
        app.buttons["household.create"].tap()

        // 報銷入口在大數字、長條圖與數字磚下面，List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let reimburse = app.buttons["household.reimburse.in-memory-member-1"]
        _ = reimburse.waitForExistence(timeout: 5)
        for _ in 0..<8 where !(reimburse.exists && reimburse.isHittable) { app.swipeUp() }
        XCTAssertTrue(reimburse.exists, "自己的代墊款沒有報銷入口")
        reimburse.tap()
        let note = app.textFields["reimbursement.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "沒有打開撥款報銷")
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "點備註欄後沒有出現鍵盤")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "備註欄按「完成」後，鍵盤沒有收起")
    }

    /// 報銷沖帳逐筆勾選(上游 d0424df、#242):有待報銷明細時列出明細、預設全選、報銷金額跟著勾選連動;
    /// 全部取消時不能送出。多個墊付帳戶的分組、「僅選此帳戶」與送出由 `ReimbursementSelectionTests` 驗證。
    @MainActor
    func testReimbursementItemSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession", "-uiTestingJoinedHousehold"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["家庭"].tap()
        let reimburse = app.buttons["household.reimburse.in-memory-member-1"]
        _ = reimburse.waitForExistence(timeout: 5)
        for _ in 0..<8 where !(reimburse.exists && reimburse.isHittable) { app.swipeUp() }
        XCTAssertTrue(reimburse.exists, "自己的代墊款沒有報銷入口")
        reimburse.tap()

        let item = app.switches["reimbursement.item.sample-advance"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "沒有列出待報銷的代墊明細")
        XCTAssertEqual(item.value as? String, "1", "代墊明細預設沒有全選")
        XCTAssertTrue(row("報銷金額", value: "250 元", in: app).exists, "報銷金額不是勾選明細的加總")
        XCTAssertFalse(app.textFields["reimbursement.amount"].exists, "有明細時報銷金額還能手動輸入")

        flip(item)
        XCTAssertTrue(waitForValue("0", of: item), "取消勾選後開關沒有關掉:\(String(describing: item.value))")
        XCTAssertTrue(row("報銷金額", value: "0 元", in: app).waitForExistence(timeout: 3), "取消勾選後報銷金額沒有跟著變")
        XCTAssertTrue(element(in: app, labelContaining: "請至少勾選一筆要報銷的代墊明細").exists, "全部取消沒有說明為什麼不能送出")
        XCTAssertFalse(app.buttons["reimbursement.submit"].isEnabled, "全部取消勾選還能送出")

        flip(item)
        XCTAssertTrue(waitForValue("1", of: item), "重新勾選後開關沒有打開:\(String(describing: item.value))")
        XCTAssertTrue(row("報銷金額", value: "250 元", in: app).waitForExistence(timeout: 3))

        // 帳戶選擇與送出(帶被勾選明細的 ID)由 testReimburseAnotherMembersAdvance 與 ReimbursementSelectionTests 驗證。
    }

    /// 開關在列的最右邊:點整列的中央會落在標籤上，改點開關本身所在的右側。
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    @MainActor
    private func waitForValue(_ expected: String, of element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expected)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
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
