import XCTest

/// 總覽的骨架屏跟載入後的版面一樣(#201):數字磚的欄數、功能入口的格數與欄數。
/// `-uiTestingHoldOverview` 讓帳戶查詢停 20 秒,骨架屏停留夠久才量得到;`-uiTesting` 下骨架不對 VoiceOver 隱藏,查得到每一格的位置。
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
