import XCTest

/// 週期收支的視角、建立者・歸屬與編輯權限(上游 ADR 0016、#152)。
/// 資料來自 `InMemoryRecurringRepository.sample(includesFamilyEntries:)`:範例帳號建立的房租(家庭公帳)、年繳保費、薪水,
/// 加上家人(小美)建立的家庭公帳「網路費」。
final class RecurringScopeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 視角篩選:全部有家人的家庭公帳;家庭公帳只有家庭公帳;個人私帳只有我的個人私帳。分攤平滑跟著變。
    @MainActor
    func testScopeFilterChangesTheListAndSummary() throws {
        let app = openRecurring(memberRole: true)
        XCTAssertTrue(item("房租", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(item("網路費", in: app).exists, "全部視角應該看得到家人的家庭公帳")
        XCTAssertTrue(item("年繳保費", in: app).exists)

        let filter = app.buttons["recurring.scope"]
        XCTAssertEqual(filter.value as? String, "全部")
        filter.tap()
        app.buttons["家庭公帳"].tap()
        XCTAssertTrue(item("網路費", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(item("房租", in: app).exists)
        XCTAssertTrue(item("年繳保費", in: app).waitForNonExistence(timeout: 5), "家庭公帳視角不該有個人私帳")
        XCTAssertTrue(element(in: app, labelContaining: "週期支出的分攤平滑 12,899 元").waitForExistence(timeout: 5), "分攤平滑沒有跟著視角")

        filter.tap()
        app.buttons["個人私帳"].tap()
        XCTAssertTrue(item("年繳保費", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(item("網路費", in: app).waitForNonExistence(timeout: 5), "個人私帳視角不該有家人的項目")
        XCTAssertTrue(item("房租", in: app).waitForNonExistence(timeout: 5), "房租是家庭公帳，個人私帳視角不該有")
        XCTAssertEqual(filter.value as? String, "個人私帳")
    }

    /// 每一項寫「建立者・歸屬」(看得到的字,自己建立的也有),VoiceOver 念出建立者與歸屬。
    @MainActor
    func testRowsShowOwnerAndOwnership() throws {
        let app = openRecurring(memberRole: true)
        let mei = item("網路費", in: app)
        XCTAssertTrue(mei.waitForExistence(timeout: 5))
        XCTAssertTrue(mei.label.contains("建立者 小美，家庭公帳"), "VoiceOver 沒念建立者與歸屬:\(mei.label)")
        XCTAssertTrue(ScrollSupport.revealFully(mei, in: app))
        let meiText = try TextRecognition.lines(in: mei.screenshot().image).joined(separator: " ")
        XCTAssertTrue(meiText.contains("小美") && meiText.contains("家庭公帳"), "家人建立的列沒有「小美・家庭公帳」:\(meiText)")

        let rent = item("房租", in: app)
        XCTAssertTrue(rent.label.contains("建立者 小明，家庭公帳"), "自己建立的也要有建立者:\(rent.label)")
        let insurance = item("年繳保費", in: app)
        XCTAssertTrue(insurance.label.contains("建立者 小明，個人私帳"), insurance.label)
    }

    /// 一般成員點家人建立的家庭公帳:跳出說明、沒有左滑刪除與長按選單、整句不塞原因;自己的照舊點得開。
    @MainActor
    func testMemberCannotEditFamilyItemButGetsAnExplanation() throws {
        let app = openRecurring(memberRole: true)
        let mei = item("網路費", in: app)
        XCTAssertTrue(mei.waitForExistence(timeout: 5))
        XCTAssertFalse(mei.label.contains("僅建立者"), "整句不該塞原因:\(mei.label)")
        mei.tap()
        let alert = app.alerts["不能編輯這個週期收支"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "點了沒有說明")
        XCTAssertTrue(alert.staticTexts["他人建立的家庭公帳，僅建立者或家庭管理員可以編輯、刪除。"].exists, alert.debugDescription)
        XCTAssertFalse(app.textFields["recurringEditor.name"].exists, "點不開的項目卻打開了編輯器")
        alert.buttons["好"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))

        mei.swipeLeft()
        XCTAssertFalse(app.buttons["刪除"].waitForExistence(timeout: 1), "點不開的項目不該有左滑刪除")
        mei.press(forDuration: 1.0)
        XCTAssertFalse(app.buttons["編輯"].waitForExistence(timeout: 1), "點不開的項目不該有長按選單")

        item("房租", in: app).tap()
        XCTAssertTrue(app.textFields["recurringEditor.name"].waitForExistence(timeout: 3), "自己建立的家庭公帳要點得開")
    }

    /// 家庭管理員改得了家人建立的家庭公帳。
    @MainActor
    func testAdminCanEditFamilyItem() throws {
        let app = openRecurring(memberRole: false)
        let mei = item("網路費", in: app)
        XCTAssertTrue(mei.waitForExistence(timeout: 5))
        // 角色在登入時問一次,晚一點才到。
        let deadline = Date().addingTimeInterval(8)
        while app.alerts.count == 0, !app.textFields["recurringEditor.name"].exists, Date() < deadline {
            mei.tap()
            if app.textFields["recurringEditor.name"].waitForExistence(timeout: 2) { break }
            if app.alerts["不能編輯這個週期收支"].exists { app.alerts.buttons["好"].tap() }
        }
        XCTAssertTrue(app.textFields["recurringEditor.name"].exists, "家庭管理員點家人建立的家庭公帳應該打開編輯器")
    }

    /// 無障礙字級:週期收支列堆疊,金額在最下面一行、靠右。
    @MainActor
    func testAmountIsOnTheBottomRightAtAX5() throws {
        let app = openRecurring(memberRole: true, category: "UICTContentSizeCategoryAccessibilityXXXL")
        let rent = item("房租", in: app)
        for _ in 0..<10 where !rent.exists { app.swipeUp() }
        XCTAssertTrue(ScrollSupport.revealFully(rent, in: app), "捲不到整列都看得到")
        let image = rent.screenshot().image
        let bands = try PixelAnalysis.inkBands(of: image)
        XCTAssertGreaterThanOrEqual(bands.count, 4, "AX5 應該是名稱、週期、建立者・歸屬、金額由上往下:\(bands)")
        let amount = try XCTUnwrap(bands.last)
        let width = Int(image.size.width * image.scale)
        let gap = width - amount.maxX
        XCTAssertTrue(gap >= 6 * Int(image.scale) && gap <= 40 * Int(image.scale), "金額沒有靠右:右邊空 \(gap) 畫素")
        XCTAssertGreaterThan(amount.minX, width / 3, "金額貼在左邊:\(amount)")
    }

    /// 新增表單的歸屬(#154):內嵌兩列，勾勾是粉紅;預設隨視角;選了家庭公帳的資產帳戶自動帶成家庭公帳，個人帳戶帶成個人私帳。
    @MainActor
    func testOwnershipRowsDefaultAndFollowTheChosenAccount() throws {
        let app = openRecurring(memberRole: false)
        app.buttons["recurring.add"].tap()
        let name = app.textFields["recurringEditor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3), "沒有打開編輯器")
        let household = app.buttons["家庭公帳"], personal = app.buttons["個人私帳"]
        for _ in 0..<6 where !(household.exists && household.isHittable) { app.swipeUp() }
        XCTAssertTrue(household.exists && personal.exists, "表單沒有歸屬的兩列")
        XCTAssertTrue(personal.isSelected, "全部視角新增時，歸屬預設是個人私帳")
        if app.keyboards.firstMatch.exists, app.buttons["完成"].firstMatch.exists { app.buttons["完成"].firstMatch.tap() }
        XCTAssertTrue(ScrollSupport.revealFully(personal, in: app, inSheet: true), "捲不到歸屬那一列")
        XCTAssertGreaterThan(try PixelAnalysis.statistics(of: personal.screenshot().image).ci, 30, "選取那列的勾勾不是粉紅")
        XCTAssertEqual(try PixelAnalysis.statistics(of: household.screenshot().image).ci, 0, "沒選的那列也有粉紅")

        let account = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "關聯帳戶")).firstMatch
        for _ in 0..<6 where !(account.exists && account.isHittable) { app.swipeUp() }
        account.tap()
        let joint = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "小美的共同基金")).firstMatch
        XCTAssertTrue(joint.waitForExistence(timeout: 3), "帳戶清單沒有家庭共同基金")
        joint.tap()
        for _ in 0..<6 where !household.isHittable { app.swipeUp() }
        XCTAssertTrue(household.isSelected, "選了家庭公帳的帳戶，歸屬沒有自動帶成家庭公帳")

        // 手動改回個人私帳;再選個人帳戶，會依帳戶重新帶入。
        personal.tap()
        XCTAssertTrue(personal.isSelected, "手動改歸屬沒有生效")
    }

    // MARK: 輔助

    @MainActor
    private func openRecurring(memberRole: Bool, category: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-uiTestingFamilyEntries", "-resetSession"]
            + (memberRole ? ["-uiTestingMemberRole"] : [])
            + (category.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        app.launch()
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("secret123")
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 5), "登入後沒有進入 tab 外殼")
        app.openPlanning()
        app.buttons["週期收支"].tap()
        return app
    }

    /// 週期收支列(按鈕,VoiceOver 整句以名稱開頭)。
    @MainActor
    private func item(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(name)，")).firstMatch
    }

    @MainActor
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
