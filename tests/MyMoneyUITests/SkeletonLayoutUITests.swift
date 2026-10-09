import XCTest

/// 總覽的骨架屏跟載入後的版面一樣(#201):數字磚的欄數、功能入口的格數與欄數。
/// `-uiTestingHoldOverview` 讓帳戶查詢停 30 秒,骨架屏停留夠久才量得到;`-uiTesting` 下骨架不對 VoiceOver 隱藏,查得到每一格的位置。
final class SkeletonLayoutUITests: XCTestCase {
    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let entryDestinations = ["recurring", "goals", "forecast"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(reset: Bool, size: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingHoldOverview"] + (reset ? ["-resetSession"] : [])
            + (size.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        app.launch()
        return app
    }

    /// 同一排(minY 相差不到 2pt)的元素有幾個:就是欄數。
    @MainActor
    private func columns(_ elements: [XCUIElement]) -> Int {
        guard let first = elements.first else { return 0 }
        return elements.filter { abs($0.frame.minY - first.frame.minY) < 2 }.count
    }

    @MainActor
    private func element(_ app: XCUIApplication, id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// 量骨架,再等載入完成量真實畫面,兩者要一樣。
    @MainActor
    private func assertSkeletonMatchesLoaded(_ app: XCUIApplication, _ name: String) {
        let skeletonTiles = (0..<3).map { element(app, id: "overview.skeleton.tile.\($0)") }
        XCTAssertTrue(skeletonTiles[0].waitForExistence(timeout: 10), "\(name):沒有看到骨架屏的數字磚")
        let skeletonTileColumns = columns(skeletonTiles)
        let skeletonEntries = Self.entryDestinations.map { element(app, id: "overview.skeleton.entry.\($0)") }
        // 入口在數字磚下面,可能要捲一下才建立;骨架一共幾格由是否存在判斷。
        for entry in skeletonEntries { _ = ScrollSupport.revealFully(entry, in: app) }
        let existingSkeletonEntries = skeletonEntries.filter(\.exists)
        XCTAssertEqual(existingSkeletonEntries.count, 3, "\(name):骨架的功能入口不是 3 格")
        let skeletonEntryColumns = columns(existingSkeletonEntries)
        XCTAssertFalse(element(app, id: "overview.skeleton.entry.ledger").exists, "\(name):骨架還有已經移除的入口")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(name) 骨架 磚\(skeletonTileColumns)欄 入口\(skeletonEntryColumns)欄"
        attachment.lifetime = .keepAlways
        add(attachment)

        // 載入完成:真實的磚(用 VoiceOver 的正名找)與入口。
        let loadedTiles = ["真實可支配現金", "當月淨收支", "信用卡待繳"].map {
            app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", $0)).firstMatch
        }
        XCTAssertTrue(loadedTiles[0].waitForExistence(timeout: 45), "\(name):載入後沒有看到數字磚")
        XCTAssertFalse(skeletonTiles[0].exists, "\(name):載入完成後骨架還在")
        XCTAssertEqual(columns(loadedTiles), skeletonTileColumns, "\(name):數字磚的欄數載入前(\(skeletonTileColumns))與載入後(\(columns(loadedTiles)))不同")
        let loadedEntries = Self.entryDestinations.map { element(app, id: "home.entry.\($0)") }
        for entry in loadedEntries { _ = ScrollSupport.revealFully(entry, in: app) }
        XCTAssertEqual(loadedEntries.filter(\.exists).count, 3)
        XCTAssertEqual(columns(loadedEntries), skeletonEntryColumns, "\(name):功能入口的欄數載入前後不同")
    }

    @MainActor
    func testSkeletonMatchesLoadedLayoutOnFirstLaunch() throws {
        let app = launch(reset: true)
        app.signInWithSampleAccount()
        assertSkeletonMatchesLoaded(app, "一般字級(第一次使用,沒有記錄)")
    }

    @MainActor
    func testSkeletonMatchesLoadedLayoutAtAX5() throws {
        let app = launch(reset: true, size: Self.ax5)
        app.signInWithSampleAccount()
        assertSkeletonMatchesLoaded(app, "AX5")
    }

    /// 第二次打開 app:骨架用上一次載入完成時記下的排法。
    @MainActor
    func testSkeletonUsesTheRememberedLayoutOnRelaunch() throws {
        let first = launch(reset: true)
        first.signInWithSampleAccount()
        assertSkeletonMatchesLoaded(first, "第一次")
        first.terminate()

        let second = launch(reset: false)
        assertSkeletonMatchesLoaded(second, "重開 app(有記錄)")
    }
}

/// 帳戶頁與家庭頁的骨架屏(#204):跟載入後一樣的排法、張數與形狀。
final class AccountsHouseholdSkeletonUITests: XCTestCase {
    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(reset: Bool, size: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (reset ? ["-resetSession"] : []) + extra
            + (size.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        app.launch()
        return app
    }

    @MainActor
    private func columns(_ elements: [XCUIElement]) -> Int {
        guard let first = elements.first else { return 0 }
        return elements.filter { abs($0.frame.minY - first.frame.minY) < 2 }.count
    }

    @MainActor
    private func any(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    @MainActor
    private func skeletonTileColumns(_ app: XCUIApplication, prefix: String, titles: [String]) -> Int {
        let tiles = titles.map { any(app, "\(prefix).\($0)") }
        if !tiles[0].waitForExistence(timeout: 15) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "沒有骨架 \(prefix)"
            shot.lifetime = .keepAlways
            add(shot)
            XCTFail("沒有看到骨架屏的數字磚(\(prefix))")
        }
        return columns(tiles)
    }

    @MainActor
    private func loadedTileColumns(_ app: XCUIApplication, labels: [String]) -> Int {
        let tiles = labels.map { app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", $0)).firstMatch }
        XCTAssertTrue(tiles[0].waitForExistence(timeout: 45), "載入後沒有看到數字磚")
        return columns(tiles)
    }

    /// 帳戶頁:磚的欄數載入前後一樣(一般與 AX5)。
    @MainActor
    func testAccountsTilesMatchTheLoadedLayout() throws {
        for size in [nil, Self.ax5] as [String?] {
            let app = launch(reset: true, size: size, extra: ["-uiTestingHoldOverview"])
            app.signInWithSampleAccount()
            app.tabBars.buttons["帳戶"].tap()
            let before = skeletonTileColumns(app, prefix: "accounts.skeleton.tile", titles: ["現金", "活存帳戶", "信用卡待繳"])
            let after = loadedTileColumns(app, labels: ["現金總額", "活存帳戶餘額合計", "信用卡待繳總額"])
            XCTAssertEqual(before, after, "帳戶頁數字磚的欄數載入前(\(before))與載入後(\(after))不同(\(size ?? "一般字級"))")
            app.terminate()
        }
    }

    /// 帳戶頁:第一次用預設張數(活存帳戶 1、信用卡 1),重開 app 後用上次的張數(範例資料:活存帳戶 1、信用卡 2)。
    @MainActor
    func testAccountsSkeletonCardCountFollowsTheLastLoad() throws {
        let first = launch(reset: true, extra: ["-uiTestingHoldOverview"])
        first.signInWithSampleAccount()
        first.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(any(first, "accounts.skeleton.card").waitForExistence(timeout: 15), "第一次沒有看到骨架屏的卡片")
        XCTAssertEqual(first.descendants(matching: .any).matching(identifier: "accounts.skeleton.card").count, 2, "第一次沒有記錄:預設活存帳戶 1、信用卡 1")
        XCTAssertTrue(first.buttons["accounts.card.sample-card"].waitForExistence(timeout: 45), "第一次沒有載入完成")
        first.terminate()

        let second = launch(reset: false, extra: ["-uiTestingHoldOverview"])
        second.tabBars.buttons["帳戶"].tap()
        XCTAssertTrue(any(second, "accounts.skeleton.card").waitForExistence(timeout: 15), "重開後沒有看到骨架屏的卡片")
        XCTAssertEqual(second.descendants(matching: .any).matching(identifier: "accounts.skeleton.card").count, 3, "重開後照上次:活存帳戶 1、信用卡 2")
    }

    /// 家庭頁:還沒加入家庭的人看到的骨架是兩個表單的形狀;載入後也是表單。
    @MainActor
    func testHouseholdNotJoinedSkeletonIsTheForms() throws {
        let app = launch(reset: true, extra: ["-uiTestingHoldHousehold"])
        app.signInWithSampleAccount()
        app.tabBars.buttons["家庭"].tap()
        XCTAssertTrue(any(app, "household.skeleton.notJoined").waitForExistence(timeout: 15), "沒有加入家庭的骨架不是表單的形狀")
        XCTAssertTrue(app.buttons["household.create"].waitForExistence(timeout: 45), "載入後沒有「建立」鈕")
    }

    /// 家庭頁:已加入家庭的人,重開 app 後骨架是已加入的形狀(分攤建議、我的代墊三格磚),不是表單。
    @MainActor
    func testHouseholdJoinedSkeletonFollowsTheLastLoad() throws {
        let first = launch(reset: true, extra: ["-uiTestingJoinedHousehold", "-uiTestingHoldHousehold"])
        first.signInWithSampleAccount()
        first.tabBars.buttons["家庭"].tap()
        XCTAssertTrue(first.buttons["household.leave"].waitForExistence(timeout: 45) || first.staticTexts["我們家"].waitForExistence(timeout: 5), "第一次沒有載入完成")
        first.terminate()

        let second = launch(reset: false, extra: ["-uiTestingJoinedHousehold", "-uiTestingHoldHousehold"])
        second.tabBars.buttons["家庭"].tap()
        XCTAssertTrue(any(second, "household.skeleton.tile.累計代墊").waitForExistence(timeout: 15), "重開後骨架不是已加入家庭的形狀")
        XCTAssertFalse(any(second, "household.skeleton.notJoined").exists)
    }
}

/// 記帳、統計、預測、週期收支、儲蓄目標的骨架屏(#204 核對):載入中看得到骨架(「載入中」),附截圖給人核對版面;
/// 數量的記憶由單元測試(`ScreenSkeletonMemoryTests`)保證。
final class ScreenSkeletonsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func assertSkeleton(_ name: String, open: (XCUIApplication) -> Void, extra: [String] = []) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession", "-uiTestingHoldScreens"] + extra
        app.launch()
        app.signInWithSampleAccount()
        open(app)
        let loading = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "載入中")).firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 15), "\(name):沒有看到骨架屏")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(name) 骨架"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

    @MainActor func testTransactionsSkeleton() { assertSkeleton("記帳") { $0.tabBars.buttons["記帳"].tap() } }
    @MainActor func testStatisticsSkeleton() { assertSkeleton("統計") { $0.tabBars.buttons["統計"].tap() } }
    @MainActor func testForecastSkeleton() { assertSkeleton("預測") { $0.openHomeEntry("forecast") } }
    @MainActor func testRecurringSkeleton() { assertSkeleton("週期收支") { $0.openHomeEntry("recurring") } }
    @MainActor func testGoalsSkeleton() { assertSkeleton("儲蓄目標") { $0.openHomeEntry("goals") } }
}
