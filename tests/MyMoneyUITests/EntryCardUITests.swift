import XCTest

/// 明細卡第三版(#288,DESIGN.md「明細卡與輸入框」):三排——頭像｜標題｜⋯、膠囊｜金額、備註;⋯ 與金額同一個右欄、右緣對齊。
final class EntryCardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 每一列的金額右緣是同一個位置,而且跟 ⋯ 的右緣一致(⋯ 與金額同一個右欄)。
    @MainActor
    func testAmountsAndMoreMenusShareOneRightEdge() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingLongRows", "-uiTestingRowParts"], signedIn: true)
        app.tabBars.buttons["記帳"].tap()
        let window = app.windows.firstMatch.frame
        var amountEdges: [CGFloat] = []
        var menuEdges: [CGFloat] = []
        for pass in 0..<5 {
            let amounts = app.descendants(matching: .any).matching(identifier: "row.amount").allElementsBoundByIndex
            for amount in amounts where amount.exists && amount.frame.minY > window.minY + 120 && amount.frame.maxY < window.maxY - 90 {
                amountEdges.append(amount.frame.maxX)
            }
            let menus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "transactions.more.")).allElementsBoundByIndex
            for menu in menus where menu.exists && menu.frame.minY > window.minY + 120 && menu.frame.maxY < window.maxY - 90 {
                menuEdges.append(menu.frame.maxX)
            }
            if pass < 4 { app.swipeUp() }
        }
        XCTAssertGreaterThan(amountEdges.count, 3, "沒有量到足夠的列")
        XCTAssertGreaterThan(menuEdges.count, 1, "沒有量到 ⋯")
        let minAmount = try XCTUnwrap(amountEdges.min()), maxAmount = try XCTUnwrap(amountEdges.max())
        XCTAssertLessThanOrEqual(maxAmount - minAmount, 1, "金額右緣不一致:\(Set(amountEdges.map { Int($0) }).sorted())")
        let menuEdge = try XCTUnwrap(menuEdges.min())
        XCTAssertEqual(menuEdge, maxAmount, accuracy: 1, "⋯ 與金額要同一個右緣:⋯ \(Set(menuEdges.map { Int($0) }).sorted())、金額 \(maxAmount)")
    }

    /// 三排由上而下:標題、膠囊、備註,各占一排、不重疊;膠囊整排在標題下面。
    @MainActor
    func testThreeRowsGoTopToBottom() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingRowParts"], signedIn: true)
        app.tabBars.buttons["記帳"].tap()
        let title = app.descendants(matching: .any).matching(identifier: "row.title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8), "沒有標題")
        let all = { (id: String) in app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.filter { $0.exists } }
        let nextTitleY = all("row.title").map(\.frame.minY).filter { $0 > title.frame.minY + 1 }.min() ?? .greatestFiniteMagnitude
        let chips = try XCTUnwrap(all("row.chips").first { $0.frame.minY > title.frame.minY && $0.frame.minY < nextTitleY }, "沒有膠囊那一排")
        let note = try XCTUnwrap(all("row.note").first { $0.frame.minY > chips.frame.minY && $0.frame.minY < nextTitleY }, "沒有備註那一排")
        XCTAssertLessThanOrEqual(title.frame.maxY, chips.frame.minY + 1, "標題與膠囊不在不同排:\(title.frame) \(chips.frame)")
        XCTAssertLessThanOrEqual(chips.frame.maxY, note.frame.minY + 1, "膠囊與備註不在不同排:\(chips.frame) \(note.frame)")
    }

    /// 標題一行、備註一行(超過用「…」,不折行):長標題長備註的列,標題與備註的高度都只有一行。
    @MainActor
    func testTitleAndNoteStayOneLine() throws {
        let app = XCUIApplication.launchUITesting(flags: ["-uiTestingLongRows", "-uiTestingRowParts"], signedIn: true)
        app.tabBars.buttons["記帳"].tap()
        let window = app.windows.firstMatch.frame
        var checked = 0
        for pass in 0..<5 {
            for id in ["row.title", "row.note"] {
                for element in app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex
                where element.exists && element.frame.minY > window.minY + 120 && element.frame.maxY < window.maxY - 90 {
                    XCTAssertLessThan(element.frame.height, 30, "\(id) 超過一行:\(element.frame)")
                    checked += 1
                }
            }
            if pass < 4 { app.swipeUp() }
        }
        XCTAssertGreaterThan(checked, 6, "沒有量到足夠的標題與備註")
    }
}

/// 編輯頁的建立時間(#290):灰字、唯讀,沒有輸入框。
extension EntryCardUITests {
    @MainActor
    func testEditorShowsReadOnlyCreatedAt() throws {
        let app = XCUIApplication.launchUITesting(signedIn: true)
        app.tabBars.buttons["記帳"].tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "午餐")).firstMatch
        XCTAssertTrue(ScrollSupport.revealFully(row, in: app), "記帳頁沒有「午餐」")
        row.tap()
        let createdAt = app.descendants(matching: .any)["form.createdAt"]
        for _ in 0..<4 where !createdAt.exists { app.swipeUp() }
        XCTAssertTrue(createdAt.waitForExistence(timeout: 5), "編輯頁沒有建立時間")
        XCTAssertFalse((createdAt.value as? String ?? "").isEmpty, "建立時間是空的")
        XCTAssertEqual(app.textFields.matching(identifier: "form.createdAt").count, 0, "建立時間不該是輸入框")
    }
}
