import XCTest

/// 資產帳戶表單的代表色列(#71):8 種代表色都看得到、選得到。
///
/// 「完整看得到」是色塊按鈕的範圍整個落在視窗裡，也在代表色那一列(表單的 cell)裡，沒有被裁掉。
/// 色塊用 VoiceOver 念的顏色名稱找，所以也順便驗證了每顆都念得出名稱、已選的標記為已選取。
final class AccountColorUITests: XCTestCase {
    /// web 的 8 種代表色(ACCOUNT_COLORS),由左到右。
    private let colorNames = ["珊瑚粉", "杏桃", "天空藍", "薄荷綠", "玫瑰紅", "檸檬黃", "淺綠", "薰衣草"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// iPhone 直向放不下一行：打開時已選的顏色完整看得到;每顆都能捲進畫面，點了就是已選取的那一個。
    @MainActor
    func testEveryAccountColorCanBeScrolledIntoViewAndSelected() throws {
        let app = launchAndOpenNewBankAccount()
        let row = colorRow(in: app)

        // 新增活存帳戶的代表色是 8 色隨機挑一個;打開時就要捲到它，打勾完整看得到。
        let initiallySelected = selectedSwatches(in: app)
        XCTAssertEqual(initiallySelected.count, 1, "新增活存帳戶時，代表色不是剛好選了一個")
        let selected = initiallySelected.firstMatch
        XCTAssertTrue(isFullyVisible(selected, in: row, app: app), "打開時已選的「\(selected.label)」沒有完整看得到：\(selected.frame)")
        XCTAssertTrue(showsPartialSwatch(in: row, app: app), "打開時(已選「\(selected.label)」)邊緣沒有露出部分色塊，看不出還能滑")

        for name in colorNames {
            let swatch = app.buttons[name]
            XCTAssertTrue(swatch.exists, "代表色列沒有「\(name)」")
            scrollIntoView(swatch, row: row, app: app)
            XCTAssertTrue(
                isFullyVisible(swatch, in: row, app: app),
                "「\(name)」捲不進畫面：色塊 \(swatch.frame),代表色列 \(row.frame),視窗 \(app.windows.firstMatch.frame)"
            )
            // 觸控範圍(色塊按鈕的範圍)至少 44×44 pt,點圓形外面、觸控範圍裡的角落也選得到。
            // frame 會有浮點誤差(例如 43.99999999999994),容許 0.5 pt。
            XCTAssertGreaterThanOrEqual(swatch.frame.width, 43.5, "「\(name)」的觸控範圍不到 44 pt 寬：\(swatch.frame)")
            XCTAssertGreaterThanOrEqual(swatch.frame.height, 43.5, "「\(name)」的觸控範圍不到 44 pt 高：\(swatch.frame)")
            tapOutsideCircle(swatch)
            XCTAssertTrue(swatch.isSelected, "點了「\(name)」圓形外、44 pt 觸控範圍裡的角落，沒有標記為已選取")
            XCTAssertEqual(selectedSwatches(in: app).count, 1, "點了「\(name)」之後，已選取的代表色不只一個")
        }
    }

    /// 編輯既有的資產帳戶：打開就捲到已選的顏色，打勾完整看得到，不用自己滑;邊緣照樣露出部分色塊。
    /// 「薰衣草」在最右邊，沒有自動捲動就在畫面外;「玫瑰紅」在中間，捲到它時兩端都還有色塊沒露出來。
    @MainActor
    func testEditingAccountScrollsToSelectedColor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "活存帳戶餘額合計").waitForExistence(timeout: 5))

        // 活存帳戶區塊在現金區塊下面，捲下去才在 UI 階層裡。
        let bank = element(in: app, labelContaining: "iOS 測試存款,餘額 50,000 元")
        for name in ["薰衣草", "玫瑰紅"] {
            // 把代表色改成這個顏色後儲存。
            XCTAssertTrue(swipeUntilHittable(bank, in: app), "帳戶頁沒有範例的活存帳戶")
            bank.tap()
            let swatch = app.buttons[name]
            XCTAssertTrue(swatch.waitForExistence(timeout: 3), "沒有打開編輯資產帳戶")
            scrollIntoView(swatch, row: colorRow(in: app), app: app)
            swatch.tap()
            XCTAssertTrue(swatch.isSelected, "點了「\(name)」之後沒有標記為已選取")
            app.buttons["accountEditor.save"].tap()
            XCTAssertTrue(swatch.waitForNonExistence(timeout: 5), "儲存後編輯資產帳戶沒有關閉")

            // 再打開同一個帳戶：不滑動，剛存的顏色就完整看得到，而且是已選取。
            XCTAssertTrue(swipeUntilHittable(bank, in: app), "儲存後帳戶頁沒有範例的活存帳戶")
            bank.tap()
            XCTAssertTrue(swatch.waitForExistence(timeout: 3), "沒有再打開編輯資產帳戶")
            let row = colorRow(in: app)
            XCTAssertTrue(swatch.isSelected, "再打開時代表色不是剛存的「\(name)」")
            XCTAssertTrue(isFullyVisible(swatch, in: row, app: app), "打開時沒有捲到已選的「\(name)」:色塊 \(swatch.frame),代表色列 \(row.frame)")
            XCTAssertTrue(showsPartialSwatch(in: row, app: app), "打開時(已選「\(name)」)邊緣沒有露出部分色塊，看不出還能滑")
            app.buttons["關閉"].tap()
            XCTAssertTrue(swatch.waitForNonExistence(timeout: 5), "按關閉後編輯資產帳戶沒有關閉")
        }
    }

    /// 橫向放得下一行：8 顆排成一行，不用滑就全部完整看得到。
    @MainActor
    func testAccountColorsFitInOneRowInLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { await MainActor.run { XCUIDevice.shared.orientation = .portrait } }
        let app = launchAndOpenNewBankAccount()
        let row = colorRow(in: app)

        let midY = app.buttons[colorNames[0]].frame.midY
        for name in colorNames {
            let swatch = app.buttons[name]
            XCTAssertTrue(isFullyVisible(swatch, in: row, app: app), "橫向時「\(name)」沒有完整看得到：\(swatch.frame),代表色列 \(row.frame)")
            XCTAssertEqual(swatch.frame.midY, midY, accuracy: 1, "橫向時「\(name)」沒有跟其他色塊排在同一行")
        }
    }

    // MARK: - 輔助

    @MainActor
    private func launchAndOpenNewBankAccount() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(app.buttons["accounts.add"].waitForExistence(timeout: 5), "帳戶頁沒有「+」")
        app.buttons["accounts.add"].tap()
        app.buttons["新增活存帳戶"].tap()
        XCTAssertTrue(app.textFields["accountEditor.name"].waitForExistence(timeout: 3), "沒有打開新增資產帳戶")
        // 橫向時代表色列在表單下方，還沒捲到的列不在 UI 階層裡。
        let first = app.buttons[colorNames[0]]
        let form = app.collectionViews.containing(.textField, identifier: "accountEditor.name").firstMatch
        for _ in 0..<4 where !(first.exists && first.isHittable) {
            form.swipeUp()
        }
        XCTAssertTrue(first.exists, "新增資產帳戶沒有代表色列")
        return app
    }

    /// 代表色那一列:表單裡含有色塊的 cell。
    @MainActor
    private func colorRow(in app: XCUIApplication) -> XCUIElement {
        let row = app.cells.containing(NSPredicate(format: "label == %@", colorNames[0])).firstMatch
        XCTAssertTrue(row.exists, "找不到代表色那一列")
        return row
    }

    /// 已選取的代表色。
    @MainActor
    private func selectedSwatches(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label IN %@ AND selected == true", colorNames))
    }

    /// 色塊的範圍整個落在視窗裡，也在代表色列裡(容許 0.5 pt 的誤差)。
    @MainActor
    private func isFullyVisible(_ swatch: XCUIElement, in row: XCUIElement, app: XCUIApplication) -> Bool {
        let frame = swatch.frame
        let visible = row.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: -0.5, dy: -0.5)
        return visible.contains(frame)
    }

    /// 有一顆色塊的圓形(直徑 32 pt,在按鈕範圍的正中間)只露出一部分：被代表色列的邊緣切到。
    @MainActor
    private func showsPartialSwatch(in row: XCUIElement, app: XCUIApplication) -> Bool {
        let visible = row.frame.intersection(app.windows.firstMatch.frame)
        return colorNames.contains { name in
            let frame = app.buttons[name].frame
            let circle = CGRect(x: frame.midX - 16, y: frame.midY - 16, width: 32, height: 32)
            let shown = circle.intersection(visible)
            return !shown.isNull && shown.width >= 1 && shown.width <= circle.width - 1
        }
    }

    /// 在代表色列上左右滑，直到色塊完整看得到(最多滑 4 次;滑不動就維持原樣，交給呼叫端判斷)。
    @MainActor
    private func scrollIntoView(_ swatch: XCUIElement, row: XCUIElement, app: XCUIApplication) {
        for _ in 0..<4 where !isFullyVisible(swatch, in: row, app: app) {
            if swatch.frame.midX < row.frame.midX {
                row.swipeRight()
            } else {
                row.swipeLeft()
            }
        }
    }

    /// 點色塊的圓形(直徑 32 pt)外面、44 pt 觸控範圍裡：從圓心往右下各偏 19 pt。
    @MainActor
    private func tapOutsideCircle(_ swatch: XCUIElement) {
        swatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 19, dy: 19)).tap()
    }

    /// 帳戶頁 List 還沒捲到的列不在 UI 階層裡，往上滑到點得到為止。
    @MainActor
    private func swipeUntilHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<5 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        return element.exists && element.isHittable
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
