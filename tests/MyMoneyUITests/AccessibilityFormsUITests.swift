import UIKit
import XCTest

/// 最大的無障礙字級(AX5)下的表單(#157 逐頁 HIG 審查):
/// - 日期列(#161)不能比卡片寬、兩側被切掉:記一筆、ATM 提款／轉帳、信用卡還款、報銷、儲蓄目標的截止日、記帳篩選的起日與迄日。
/// - 備註欄(#170)的值不能被截成「…」:信用卡還款與報銷的預設備註很長,記一筆輸入長備註之後也一樣。
///
/// 畫面上實際寫了什麼 accessibility 看不到,所以用截圖的像素與 OCR 驗證。
final class AccessibilityFormsUITests: XCTestCase {
    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: 日期列(#161)

    @MainActor
    func testQuickEntryDateRowFitsAtAX5() throws {
        let app = launchSignedIn()
        app.buttons["overview.add"].tap()
        waitForSheet(app, "記一筆")
        try assertDateRowFits("日期", app: app)
    }

    @MainActor
    func testTransferDateRowFitsAtAX5() throws {
        let app = launchSignedIn()
        app.tabBars.buttons["帳戶"].tap()
        let transfer = app.buttons["accounts.transfer"]
        XCTAssertTrue(ScrollSupport.revealFully(transfer, in: app), "帳戶頁沒有 ATM 提款／轉帳")
        transfer.tap()
        waitForSheet(app, "轉帳")
        try assertDateRowFits("日期", app: app)
    }

    @MainActor
    func testCardPaymentDateRowFitsAtAX5() throws {
        let app = launchSignedIn()
        try openCardPayment(in: app)
        try assertDateRowFits("日期", app: app)
    }

    @MainActor
    func testReimbursementDateRowFitsAtAX5() throws {
        let app = launchSignedIn(extraArguments: ["-uiTestingJoinedHousehold"])
        try openReimbursement(in: app)
        try assertDateRowFits("撥款日期", app: app)
    }

    @MainActor
    func testGoalDeadlineRowFitsAtAX5() throws {
        let app = launchSignedIn()
        app.openHomeEntry("goals")
        let add = app.buttons["goals.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "沒有儲蓄目標頁")
        add.tap()
        let toggle = app.switches["截止日"]
        XCTAssertTrue(ScrollSupport.revealFully(toggle, in: app, inSheet: true), "建立目標沒有「截止日」開關")
        // 開關在整列的最右邊:點那裡才一定切換。
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let on = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [on], timeout: 3), .completed, "「截止日」開關沒有打開:\(String(describing: toggle.value))")
        waitForSheet(app, "建立目標")
        try assertDateRowFits("日期", app: app)
    }

    @MainActor
    func testFilterDateRowsFitAtAX5() throws {
        let app = launchSignedIn()
        app.tabBars.buttons["記帳"].tap()
        let filter = app.buttons["transactions.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5), "記帳頁沒有篩選鈕")
        filter.tap()
        waitForSheet(app, "篩選")
        expandSheet(app)
        try assertDateRowFits("起日", app: app)
        try assertDateRowFits("迄日", app: app)
    }

    // MARK: 備註(#170)

    @MainActor
    func testCardPaymentNoteIsNotTruncatedAtAX5() throws {
        let app = launchSignedIn()
        try openCardPayment(in: app)
        try assertNoteShowsEverything("cardPayment.note", ending: "全額", app: app)
    }

    @MainActor
    func testReimbursementNoteIsNotTruncatedAtAX5() throws {
        let app = launchSignedIn(extraArguments: ["-uiTestingJoinedHousehold"])
        try openReimbursement(in: app)
        try assertNoteShowsEverything("reimbursement.note", ending: "代墊公帳", app: app)
    }

    @MainActor
    func testQuickEntryLongNoteIsNotTruncatedAtAX5() throws {
        let app = launchSignedIn()
        app.buttons["overview.add"].tap()
        waitForSheet(app, "記一筆")
        // 一般字級是單行欄位,無障礙字級是可以長高的多行欄位:元素類型不同,用任意類型找。
        let note = app.descendants(matching: .any)["quickEntry.note"]
        XCTAssertTrue(ScrollSupport.revealFully(note, in: app, inSheet: true), "記一筆沒有備註欄")
        note.tap()
        note.typeText("週末全家一起去大賣場採買下週要用的食材")
        // 收起鍵盤(點空白處以外的欄位;備註欄不因為多行而把 Return 變成換行)。
        note.typeText("\n")
        XCTAssertFalse((note.value as? String ?? "").contains("\n"), "備註欄的 Return 變成換行了:\(String(describing: note.value))")
        try assertNoteShowsEverything("quickEntry.note", ending: "食材", app: app)
    }

    // MARK: 流程

    @MainActor
    private func launchSignedIn(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession", "-UIPreferredContentSizeCategoryName", Self.ax5] + extraArguments
        app.launch()
        app.signInWithSampleAccount()
        return app
    }

    /// 等表單的 sheet 出現(用導覽列的 ✕ 鈕判斷:sheet 的 ✕ 與 ✓ 在 sheet 自己的導覽列裡)。
    @MainActor
    private func waitForSheet(_ app: XCUIApplication, _ name: String) {
        XCTAssertTrue(app.navigationBars.buttons["關閉"].firstMatch.waitForExistence(timeout: 8), "沒有打開「\(name)」表單")
    }

    /// 篩選 sheet 一開始只有半個畫面(`.medium`):往上拉到全高,不然往上捲動只會把 sheet 拉高、內容不動。
    @MainActor
    private func expandSheet(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.49))
            .press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
    }

    /// 帳戶頁 → 信用卡 → 詳細頁「繳款」選單 → 全額結清。
    @MainActor
    private func openCardPayment(in app: XCUIApplication) throws {
        app.tabBars.buttons["帳戶"].tap()
        let card = app.buttons["accounts.card.sample-card"]
        XCTAssertTrue(ScrollSupport.revealFully(card, in: app), "帳戶頁沒有信用卡")
        card.tap()
        let pay = app.buttons["cardDetail.pay"]
        XCTAssertTrue(ScrollSupport.revealFully(pay, in: app), "詳細頁沒有「繳款」")
        pay.tap()
        let full = app.buttons["全額結清"]
        XCTAssertTrue(full.waitForExistence(timeout: 5), "「繳款」選單沒有「全額結清」")
        full.tap()
        waitForSheet(app, "信用卡扣款還款")
    }

    /// 家庭頁 → 第一位成員的「報銷沖帳」。
    @MainActor
    private func openReimbursement(in app: XCUIApplication) throws {
        app.tabBars.buttons["家庭"].tap()
        let reimburse = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "household.reimburse.")).firstMatch
        XCTAssertTrue(ScrollSupport.revealFully(reimburse, in: app), "家庭頁沒有「報銷沖帳」")
        reimburse.tap()
        waitForSheet(app, "報銷")
    }

    // MARK: 量測

    /// 日期列在卡片裡:截圖裡所有墨跡離卡片左右兩側至少 6pt(以前膠囊比卡片寬,文字貼到卡片邊緣或被切掉)。
    /// 日期列的元素(compact 的 DatePicker 或無障礙字級的整列按鈕)標籤以「日期」之類的標題開頭;截圖用包住它的那一格卡片。
    @MainActor
    private func assertDateRowFits(_ title: String, app: XCUIApplication) throws {
        // 標題完全相同,或「標題,日期」這種合併念法;不能只比開頭(背景頁有「日期與時間」的圖示)。
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@", title, title + ",", title + "，")
        ).firstMatch
        XCTAssertTrue(ScrollSupport.revealFully(row, in: app, inSheet: true), "沒有找到「\(title)」這一列,或捲不到整列都看得到")
        let center = CGPoint(x: row.frame.midX, y: row.frame.midY)
        let cell = try XCTUnwrap(
            app.cells.allElementsBoundByIndex.first { $0.isHittable && $0.frame.contains(center) },
            "找不到包住「\(title)」的那一格卡片:\(row.frame)"
        )
        let full = cell.screenshot().image
        // 失敗時看得到實際畫面(量測是像素)。
        let attachment = XCTAttachment(image: full)
        attachment.name = "\(title)"
        attachment.lifetime = .keepAlways
        add(attachment)
        // 只量卡片內部的上半部:截圖的上下是卡片的圓角(灰色),最右邊是捲動條,都不是列的內容。
        // 列的標題(「日期」)在最上面;以前它被卡片切掉,墨跡從最左邊的第 0 欄開始。
        let scale = Int(full.scale)
        let cg = try XCTUnwrap(full.cgImage)
        let cropRect = CGRect(x: 0, y: 24 * scale, width: cg.width - 28 * scale / 2, height: Int(Double(cg.height) * 0.6) - 24 * scale)
        let image = UIImage(cgImage: try XCTUnwrap(cg.cropping(to: cropRect)))
        let width = cg.width - 28 * scale / 2
        // 只看字那麼高的墨跡:圓角的灰色小楔形不算(高度不到 12pt)。
        let bands = try PixelAnalysis.inkBands(of: image).filter { $0.maxY - $0.minY >= 12 * scale }
        XCTAssertFalse(bands.isEmpty, "「\(title)」這一列看不到字")
        XCTAssertTrue(
            bands.allSatisfy { $0.minX >= 6 * scale && $0.maxX <= width - 6 * scale },
            "「\(title)」這一列的字貼到卡片邊緣(被切掉了?):\(bands.map { "\($0.minX)...\($0.maxX)" }) 寬度 \(width)"
        )
    }

    /// 備註欄的值完整顯示:OCR 辨識得到結尾的字,而且沒有「…」。
    @MainActor
    private func assertNoteShowsEverything(_ identifier: String, ending: String, app: XCUIApplication) throws {
        let note = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(ScrollSupport.revealFully(note, in: app, inSheet: true), "找不到備註欄「\(identifier)」")
        let cell = app.cells.containing(.any, identifier: identifier).firstMatch
        let lines = try TextRecognition.lines(in: (cell.exists ? cell : note).screenshot().image)
        let text = lines.joined().replacingOccurrences(of: " ", with: "")
        XCTAssertTrue(text.contains(ending), "備註欄的值沒有完整顯示(看不到結尾「\(ending)」),辨識到:\(lines)")
        XCTAssertFalse(lines.contains { $0.contains("…") || $0.contains("...") }, "備註欄的值被截斷:\(lines)")
    }
}
