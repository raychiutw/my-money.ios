import XCTest

/// 截圖巡覽(#70):用 in-memory 範例資料走過每一頁和主要的 sheet,每一屏拍一張，存成測試結果的 attachment。
///
/// 這是開發工具，不是正式測試：沒有設環境變數 `SCREEN_TOUR_CONTENT_SIZE` 就 skip,所以一般的 `xcodebuild test` 和 CI 不跑它。
/// 用 `scripts/screen-tour.sh` 跑：script 切換模擬器的外觀和字級，每種組合跑一次，再把截圖匯出成 PNG(DESIGN.md「截圖巡覽」)。
/// 字級由環境變數指定(例如 `UICTContentSizeCategoryXXL`),透過 launch argument 傳給 app;深淺色照模擬器的外觀。
///
/// - 只開畫面、捲動、按「取消」或系統的返回，不按任何儲存或送出。
/// - 返回一律點系統的返回按鈕。不要點「所有導覽列的第一顆按鈕」:sheet 底下那一層的導覽列也算，會點到總覽的「+」。
/// - 每一屏拍一張：往上拖半個畫面再拍，UI 階層跟上一張一樣就是到底了。
/// - attachment 的名稱是「畫面-序號」,例如 `accounts-02`;script 匯出時再加上外觀和字級。
final class ScreenTourUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTour() throws {
        guard let contentSize = ProcessInfo.processInfo.environment["SCREEN_TOUR_CONTENT_SIZE"] else {
            throw XCTSkip("截圖巡覽只由 scripts/screen-tour.sh 執行(沒有設 SCREEN_TOUR_CONTENT_SIZE)")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession", "-UIPreferredContentSizeCategoryName", contentSize]
        app.launch()
        let tour = Tour(app: app, testCase: self)

        // 登入頁、註冊頁。
        XCTAssertTrue(app.textFields["login.email"].waitForExistence(timeout: 10), "沒有看到登入頁")
        tour.captureScrolling("login")
        tour.push(app.buttons["login.register"], capturing: "register")
        tour.signIn()

        // 總覽，以及從總覽打開的記一筆、「我的」sheet(機器人記帳、模擬對話)。
        tour.captureScrolling("overview")
        // 記一筆:歸屬是內嵌選擇列、分類是格狀;帳戶點進去是清單頁(ADR-0004)。
        tour.present(app.buttons["overview.add"], capturing: "quick-entry") {
            // 只在 collection view 裡找:sheet 後面底部 tab bar 也有一顆「帳戶」按鈕,但 tab bar 不是 collection view。
            // 不能用「含金額欄的 collection view」:字級大到要捲動時,金額欄已被回收,找不到表單。
            let account = app.collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "帳戶")).firstMatch
            tour.push(account, capturing: "quick-entry-account")
        }
        tour.tap(app.buttons["toolbar.me"])
        tour.captureScrolling("me-settings")
        tour.push(app.buttons["機器人記帳"], capturing: "bot") {
            tour.push(app.buttons["模擬對話"], capturing: "bot-chat")
        }
        tour.dismissSheet(titled: "我的")

        // 交易，以及 toolbar 篩選按鈕打開的篩選 sheet(#74)。
        tour.select(tab: "交易")
        tour.captureScrolling("transactions")
        tour.present(app.buttons["transactions.filter"], capturing: "transaction-filter")

        // 帳戶，以及新增資產帳戶(三種類型)、ATM 提款／轉帳、信用卡詳細頁和信用卡扣款還款。
        tour.select(tab: "帳戶")
        tour.captureScrolling("accounts")
        tour.present(app.buttons["accounts.add"], menuItem: "新增現金錢包", capturing: "account-editor-cash")
        tour.present(app.buttons["accounts.add"], menuItem: "新增銀行存款帳戶", capturing: "account-editor-bank")
        tour.present(app.buttons["accounts.add"], menuItem: "新增信用卡", capturing: "account-editor-card")
        tour.present(app.buttons["accounts.transfer"], capturing: "transfer")
        // 信用卡精簡列點進詳細頁(#73),信用卡扣款還款從詳細頁的「繳款」選單打開。
        // 每種組合都用同一張卡(範例資料的「iOS 測試信用卡」)、同一個項目(全額結清),改前改後才比得起來。
        tour.push(app.buttons["accounts.card.sample-card"], capturing: "card-detail") {
            tour.present(app.buttons["cardDetail.pay"], menuItem: "全額結清", capturing: "card-payment")
        }

        // 家庭(範例帳號沒有加入家庭，只拍得到建立和加入)。
        tour.select(tab: "家庭")
        tour.captureScrolling("household")

        // 統計。
        tour.select(tab: "統計")
        tour.captureScrolling("statistics")

        // 「我的」的規劃分頁，以及週期收支、儲蓄目標、現金流預測和它們的新增表單。
        tour.tap(app.buttons["toolbar.me"])
        tour.tap(app.segmentedControls["me.page"].buttons["規劃"])
        tour.captureScrolling("me-planning")
        tour.push(app.buttons["週期收支"], capturing: "recurring") {
            tour.present(app.buttons["recurring.add"], capturing: "recurring-editor")
        }
        tour.push(app.buttons["儲蓄目標"], capturing: "goals") {
            tour.present(app.buttons["goals.add"], capturing: "goal-editor")
        }
        tour.push(app.buttons["現金流預測"], capturing: "forecast")
        tour.dismissSheet(titled: "我的")
    }
}

/// 巡覽的動作：開畫面、捲動拍照、返回或取消。
@MainActor
private struct Tour {
    let app: XCUIApplication
    let testCase: XCTestCase

    /// 一個畫面最多拍幾屏;AX5 的長頁面也不會超過。
    private let maxScreens = 40

    /// 拍目前的畫面，往上拖半個畫面再拍，直到 UI 階層不再變(到底了)。
    func captureScrolling(_ screen: String) {
        settle()
        var index = 1
        attach(screen, index: index)
        var previous = fingerprint()
        while index < maxScreens {
            // 自動聚焦的欄位(例如記一筆的金額)會叫出鍵盤：在鍵盤上方拖，表單的 `scrollDismissesKeyboard` 會收起鍵盤。
            // 不在鍵盤上拖，以免按到鍵。
            if app.keyboards.firstMatch.exists {
                drag(from: 0.4, to: 0.2)
            } else {
                drag(from: 0.75, to: 0.25)
            }
            settle()
            let current = fingerprint()
            if current == previous { return }
            index += 1
            attach(screen, index: index)
            previous = current
        }
        XCTFail("「\(screen)」拍了 \(maxScreens) 屏還沒到底")
    }

    /// 登入 in-memory 的範例帳號(`InMemoryAuthRepository.Member.sample`)。
    func signIn() {
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5), "沒有看到登入頁")
        email.tap()
        email.typeText("family@example.com")
        let password = app.secureTextFields["login.password"]
        password.tap()
        // 密碼欄按 Return 就送出;大字級時登入按鈕可能被鍵盤擋住。
        password.typeText("secret123\n")
        XCTAssertTrue(app.tabBars.buttons["總覽"].waitForExistence(timeout: 10), "登入後沒有進入 tab 外殼")
    }

    func select(tab: String) {
        tap(app.tabBars.buttons[tab])
    }

    /// 點入口 push 一頁，拍完(以及 `inside` 裡的動作)之後點系統的返回按鈕回來。
    func push(_ entry: XCUIElement, capturing screen: String, inside: () -> Void = {}) {
        reveal(entry)
        tap(entry)
        captureScrolling(screen)
        inside()
        let back = app.navigationBars.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "「\(screen)」沒有系統的返回按鈕")
        back.tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "從「\(screen)」返回失敗")
    }

    /// 點入口(選單的話再點 `menuItem`)打開表單 sheet,拍完(以及 `inside` 裡的動作)按導覽列的「取消」。
    func present(_ entry: XCUIElement, menuItem: String? = nil, capturing screen: String, inside: () -> Void = {}) {
        reveal(entry)
        tap(entry)
        if let menuItem {
            tap(app.buttons[menuItem])
        }
        let cancel = app.navigationBars.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "沒有打開「\(screen)」")
        captureScrolling(screen)
        inside()
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), "「\(screen)」按取消之後沒有關閉")
    }

    /// 用導覽列的關閉鈕關掉沒有「取消」的 sheet(「我的」)。
    ///
    /// 系統的關閉鈕(`Button(role: .close)`)沒有 identifier,標籤跟著模擬器的語言;找不到才改用下滑。
    /// 下滑只在清單捲在頂端時有用：大字級時「我的」捲到底之後，在導覽列下滑只會捲動清單。
    func dismissSheet(titled title: String) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "沒有看到「\(title)」sheet")
        let close = bar.buttons.matching(NSPredicate(format: "label IN %@", ["關閉", "Close"])).firstMatch
        if close.exists {
            close.tap()
        } else {
            bar.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5), "「\(title)」sheet 沒有關閉")
    }

    func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "找不到「\(element.description)」")
        element.tap()
    }

    /// 捲到入口完整露出來為止(例如帳戶頁下方的信用卡):先往下找，找不到再往上找。
    private func reveal(_ element: XCUIElement) {
        _ = element.waitForExistence(timeout: 2)
        guard !isClear(element), !nudge(element) else { return }
        for (from, to) in [(0.75, 0.25), (0.3, 0.8)] {
            var previous = fingerprint()
            for _ in 0..<maxScreens {
                drag(from: from, to: to)
                settle()
                if isClear(element) || nudge(element) { return }
                let current = fingerprint()
                if current == previous { break }
                previous = current
            }
        }
    }

    /// 元素點得到，而且不會點到上面那一層：toolbar 的按鈕本身就在導覽列裡;清單裡的元素要在導覽列和 tab bar 之間。
    /// 導覽列和 tab bar 是透明的，底下的元素 `isHittable` 也是 true,點下去卻會點到導覽列的按鈕或切換 tab。
    private func isClear(_ element: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let bars = app.navigationBars.allElementsBoundByIndex.map(\.frame)
        if bars.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(element.frame) }) { return true }
        let (top, bottom) = contentBounds()
        return element.frame.minY >= top && element.frame.maxY <= bottom
    }

    /// 導覽列下緣到 tab bar 上緣：清單裡的元素完整露出的範圍。
    private func contentBounds() -> (top: CGFloat, bottom: CGFloat) {
        let top = app.navigationBars.allElementsBoundByIndex.map(\.frame.maxY).max() ?? 0
        let tabBar = app.tabBars.firstMatch
        let bottom = tabBar.exists ? tabBar.frame.minY : app.windows.firstMatch.frame.maxY
        return (top, bottom)
    }

    /// 元素已經在畫面上，只是被導覽列或 tab bar 擋住一部分：依擋住的距離再拖一小段。
    /// 大字級的列很高(例如 AX5 的信用卡精簡列),每次拖半個畫面，可能剛好跳過它完整露出的位置。
    private func nudge(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let (top, bottom) = contentBounds()
        let frame = element.frame
        guard frame.height < bottom - top else { return false }
        // 正數是內容往上移。多拖一點，抵掉手指開始捲動前的那一小段。
        let margin: CGFloat = 24
        let shift: CGFloat
        if frame.minY < top {
            shift = frame.minY - top - margin
        } else if frame.maxY > bottom {
            shift = frame.maxY - bottom + margin
        } else {
            return false
        }
        let height = app.windows.firstMatch.frame.height
        drag(from: 0.5, to: min(max(0.5 - shift / height, 0.05), 0.95))
        settle()
        return isClear(element)
    }

    /// 在畫面水平中央，從 `from` 拖到 `to`(畫面高度的比例)。停住再放開，不會甩出慣性，每次捲的距離固定。
    private func drag(from: CGFloat, to: CGFloat) {
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.2)
    }

    /// 等資料載入、捲動回彈和轉場結束。
    private func settle() {
        Thread.sleep(forTimeInterval: 1)
    }

    /// 畫面上有文字或識別的元素，連同位置;捲動後沒變就是到底了。
    /// - 沒有文字的容器不算：到底之後再拖，沒有標籤的捲軸位置和長短還是會變。
    /// - 位置取整數：sheet 每拖一次，位置會多出一點浮點誤差(78.00000000000003)。
    private func fingerprint() -> String {
        guard let snapshot = try? app.snapshot() else { return UUID().uuidString }
        var lines: [String] = []
        func walk(_ element: any XCUIElementSnapshot) {
            if !element.label.isEmpty || !element.identifier.isEmpty {
                let frame = element.frame
                let position = [frame.minX, frame.minY, frame.width, frame.height].map { $0.isFinite ? Int($0.rounded()) : 0 }
                lines.append("\(element.elementType.rawValue)|\(element.identifier)|\(element.label)|\(position)")
            }
            element.children.forEach(walk)
        }
        walk(snapshot)
        return lines.joined(separator: "\n")
    }

    private func attach(_ screen: String, index: Int) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "%@-%02d", screen, index)
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }
}
