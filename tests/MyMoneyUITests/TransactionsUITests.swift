import XCTest

/// 「交易」tab 與「記一筆」。資料來自 MyMoneyTestSupport 的 `SampleTransactions`(日期相對於今天，不連網路)。
final class TransactionsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 列表顯示本月的收支明細;記一筆 250 元後出現在列表上。
    @MainActor
    func testListShowsThisMonthAndQuickEntryAddsTransaction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["記帳"].tap()
        // 收支明細在大數字、比例條與長條圖下面，List 還沒捲到的列不在 UI 階層裡，先捲下去。
        let expense = element(in: app, labelContaining: "支出 880 元")
        _ = expense.waitForExistence(timeout: 5)
        for _ in 0..<6 where !expense.exists { app.swipeUp() }
        XCTAssertTrue(expense.exists, "沒有看到本月的收支明細")
        for _ in 0..<6 where !element(in: app, labelContaining: "收入 45,000 元").exists { app.swipeUp() }
        XCTAssertTrue(element(in: app, labelContaining: "收入 45,000 元").exists)
        XCTAssertTrue(element(in: app, labelContaining: "個人私帳").exists)
        for _ in 0..<8 where !app.buttons["transactions.filter"].isHittable { app.swipeDown() }
        // 預設的範圍是本月 1 號到台灣時間的今天。CI 的模擬器在 UTC,以前會顯示成前一天。
        XCTAssertEqual(
            app.buttons["transactions.filter"].value as? String, "全部・\(Self.taipeiThisMonthPeriod())",
            "篩選按鈕的 VoiceOver 值不是本月 1 號到台灣時間的今天(\(Self.taipeiThisMonthPeriod()))"
        )

        app.buttons["transactions.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        amount.tap()
        amount.typeText("250")
        app.chooseQuickEntryAccount()
        XCTAssertFalse(element(in: app, labelContaining: "(活存帳戶)").exists, "記一筆的帳戶選擇列還帶著類型")
        app.buttons["quickEntry.save"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "支出 250 元").waitForExistence(timeout: 5), "記一筆後沒有出現在列表上")
    }

    /// 篩選收進 toolbar 篩選按鈕打開的「篩選」sheet(#74):清單上方沒有分段控制，篩選按鈕的 VoiceOver 值描述目前的範圍。
    /// 在 sheet 裡改類型後按「完成」,清單、篩選按鈕的值和收支明細的筆數都更新;再改一次按「取消」,全部不變。
    @MainActor
    func testFilterSheetAppliesOnDoneAndCancelKeepsFilter() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        let period = Self.taipeiThisMonthPeriod()
        XCTAssertTrue(element(in: app, labelContaining: "支出 880 元").waitForExistence(timeout: 5), "沒有看到本月的收支明細")
        XCTAssertEqual(app.buttons["transactions.filter"].value as? String, "全部・\(period)", "篩選按鈕的 VoiceOver 值沒有描述目前的範圍(全部・\(period))")
        XCTAssertEqual(app.collectionViews.firstMatch.segmentedControls.count, 0, "交易頁的清單上方還有分段控制")
        XCTAssertTrue(app.staticTexts["收支明細(4)"].exists, "收支明細的筆數不在 section 的標題")

        let filter = app.buttons["transactions.filter"]
        XCTAssertTrue(filter.exists, "toolbar 沒有篩選按鈕")
        XCTAssertEqual(filter.label, "篩選", "篩選按鈕的 VoiceOver 標籤不是「篩選」")
        filter.tap()
        let sheet = app.navigationBars["篩選"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "點篩選按鈕沒有打開「篩選」sheet")
        XCTAssertTrue(app.segmentedControls.buttons["家庭公帳"].exists, "篩選 sheet 裡沒有視角的分段控制")
        // 迄日的 DatePicker 是台灣時間的今天。CI 的模擬器在 UTC,以前會顯示成前一天。
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "value == %@", Self.taipeiToday())).firstMatch.exists,
            "迄日不是台灣時間的今天(\(Self.taipeiToday()))"
        )
        tapRevealing(app.buttons["僅收入"], in: app)
        sheet.buttons["完成"].tap()

        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3), "按完成後篩選 sheet 沒有關閉")
        XCTAssertEqual(app.buttons["transactions.filter"].value as? String, "全部・\(period)・收入", "按完成後篩選按鈕的值沒有加上類型")
        XCTAssertTrue(element(in: app, labelContaining: "收入 45,000 元").exists, "按完成後清單沒有收入")
        XCTAssertFalse(element(in: app, labelContaining: "支出 880 元").exists, "按完成後清單還有支出")
        XCTAssertTrue(app.staticTexts["收支明細(1)"].exists, "按完成後收支明細的筆數沒有更新")

        // 改成僅支出再按取消：清單和篩選按鈕的值都不變。
        filter.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), "沒有再次打開「篩選」sheet")
        tapRevealing(app.buttons["僅支出"], in: app)
        sheet.buttons["關閉"].tap()

        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3), "按關閉後篩選 sheet 沒有關閉")
        XCTAssertEqual(app.buttons["transactions.filter"].value as? String, "全部・\(period)・收入", "按關閉後篩選按鈕的值變了")
        XCTAssertTrue(element(in: app, labelContaining: "收入 45,000 元").exists, "按關閉後清單變了")
        XCTAssertFalse(element(in: app, labelContaining: "支出 880 元").exists, "按關閉後清單變了")
    }

    /// 交易列在「家庭公帳 + 家人記的」下固定兩行(#128、#145):列高跟其他列一樣，金額不被擠到左下。
    /// 真機的字級常常不是預設的 L:並列版型在 XXL、XXXL 放不下就會掉進上下堆疊;只有無障礙字級才該堆疊。
    @MainActor
    func testFamilyRecordedPublicRowsStayTwoLinesAtXXL() throws {
        try assertFamilyRowsStayTwoLines(at: "UICTContentSizeCategoryXXL")
    }

    @MainActor
    func testFamilyRecordedPublicRowsStayTwoLinesAtXXXL() throws {
        try assertFamilyRowsStayTwoLines(at: "UICTContentSizeCategoryXXXL")
    }

    @MainActor
    private func assertFamilyRowsStayTwoLines(at category: String) throws {
        let app = XCUIApplication()
        // 有家庭才看得到家人記的交易:家庭管理員，家人記的公帳點得開，列版型才是真實使用的樣子。
        app.launchArguments = [
            "-uiTesting", "-uiTestingJoinedHousehold", "-uiTestingFamilyEntries", "-resetSession",
            "-UIPreferredContentSizeCategoryName", category,
        ]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        let lunch = element(in: app, labelContaining: "餐飲，午餐，帳戶")
        let short = element(in: app, labelContaining: "餐飲，晚餐-水煎包，帳戶")
        let long = element(in: app, labelContaining: "餐飲，週末全家一起去大賣場")
        for _ in 0..<12 where !(lunch.exists && short.exists && long.exists) { app.swipeUp() }
        XCTAssertTrue(lunch.exists && short.exists && long.exists, "沒有找到範例交易:\(lunch.exists) \(short.exists) \(long.exists)")

        // 自己記的家庭公帳(兩行基準)與家人記的家庭公帳:列高要一樣。
        XCTAssertEqual(short.frame.height, lunch.frame.height, accuracy: 4, "\(category):家人記的家庭公帳掉進上下堆疊:\(short.frame.height) vs \(lunch.frame.height)")
        // 備註很長:標題最多兩行(比基準多一行)，不是把次要文字與金額擠成額外的幾行。
        XCTAssertLessThan(long.frame.height, lunch.frame.height * 1.6, "\(category):備註很長的列高度超過標題兩行加次要文字:\(long.frame.height) vs \(lunch.frame.height)")
    }

    /// 編輯權限防呆(上游 ADR 0013、#133):家人(小美)記的家庭公帳，一般成員點不開，VoiceOver 念出原因;
    /// 家庭管理員點得開。自己記的照舊。
    @MainActor
    func testMemberCannotEditFamilyRecordedPublicRowButAdminCan() throws {
        for isAdmin in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-uiTestingFamilyEntries", "-resetSession"]
                + (isAdmin ? [] : ["-uiTestingMemberRole"])
            app.launch()
            signIn(app)
            app.tabBars.buttons["記帳"].tap()

            let role = isAdmin ? "家庭管理員" : "一般成員"
            let family = element(in: app, labelContaining: "餐飲，晚餐-水煎包，帳戶")
            let lunch = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "餐飲，午餐，帳戶")).firstMatch
            for _ in 0..<12 where !(family.exists && lunch.exists) { app.swipeUp() }
            XCTAssertTrue(lunch.exists, "\(role):自己記的公帳要點得開")
            XCTAssertTrue(family.exists, "\(role):沒有找到家人記的公帳")

            let familyButton = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "晚餐-水煎包")).firstMatch
            // 原因不再塞在整句最後(#146),VoiceOver 念提示、點了才說明。
            XCTAssertFalse(family.label.contains("僅記錄者"), "\(role):整句不該再有鎖定說明:\(family.label)")
            if isAdmin {
                // 角色在登入時問一次，晚一點才到。
                XCTAssertTrue(familyButton.waitForExistence(timeout: 5), "\(role):家人記的公帳應該點得開")
                familyButton.tap()
                XCTAssertTrue(app.buttons["quickEntry.save"].waitForExistence(timeout: 3), "\(role):點家人記的公帳沒有打開編輯")
            } else {
                // 點得到(是按鈕)，但點了跳出說明，不是編輯。
                XCTAssertTrue(familyButton.waitForExistence(timeout: 5), "\(role):點不開的列也要能點，才有說明")
                familyButton.tap()
                let alert = app.alerts["不能編輯這筆收支明細"]
                XCTAssertTrue(alert.waitForExistence(timeout: 3), "\(role):點了沒有說明")
                XCTAssertTrue(
                    alert.staticTexts["他人記錄的家庭公帳，僅記錄者或家庭管理員可以編輯、刪除。"].exists, "\(role):說明文字不對:\(alert.debugDescription)"
                )
                XCTAssertFalse(app.buttons["quickEntry.save"].exists, "\(role):點不開的列卻打開了編輯")
                alert.buttons["好"].tap()
                XCTAssertTrue(alert.waitForNonExistence(timeout: 3), "\(role):按「好」沒有關閉說明")
                // 沒有權限的列仍然沒有左滑刪除與長按選單。
                familyButton.swipeLeft()
                XCTAssertFalse(app.buttons["刪除"].waitForExistence(timeout: 1), "\(role):沒有權限的列不該有左滑刪除")
                familyButton.press(forDuration: 1.0)
                XCTAssertFalse(app.buttons["編輯"].waitForExistence(timeout: 1), "\(role):沒有權限的列不該有長按選單")
            }
            app.terminate()
        }
    }

    /// 點不開的列不影響版型(#128、#133、#145):沒有權限的家人公帳，列高跟自己記的一樣。
    @MainActor
    func testLockedFamilyRowStaysTwoLinesAtXXL() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTesting", "-uiTestingJoinedHousehold", "-uiTestingMemberRole", "-uiTestingFamilyEntries", "-resetSession",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL",
        ]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        let lunch = element(in: app, labelContaining: "餐飲，午餐，帳戶")
        let short = element(in: app, labelContaining: "餐飲，晚餐-水煎包，帳戶")
        for _ in 0..<12 where !(lunch.exists && short.exists) { app.swipeUp() }
        XCTAssertTrue(lunch.exists && short.exists, "沒有找到範例交易")
        // 量完列高再點:一般成員點不開家人的家庭公帳,點了是說明(#146),原因不在整句裡。
        XCTAssertEqual(short.frame.height, lunch.frame.height, accuracy: 4, "點不開的列掉進上下堆疊:\(short.frame.height) vs \(lunch.frame.height)")
        XCTAssertFalse(short.label.contains("僅記錄者"), "整句不該再有鎖定說明:\(short.label)")
        XCTAssertTrue(ScrollSupport.revealFully(short, in: app), "捲不到這一列")
        short.tap()
        XCTAssertTrue(app.alerts["不能編輯這筆收支明細"].waitForExistence(timeout: 3), "這一列應該是點不開的(點了要有說明)")
    }

    /// 次要文字是看得到的字(#145):「記帳人・歸屬」在標題下面，資產帳戶名稱在金額下面;系統紀錄寫「系統紀錄」。
    /// 列被合成一個 VoiceOver 元素，所以用 OCR 讀畫面上實際寫的字(只比對關鍵字詞，不比對標點)。
    @MainActor
    func testRowsShowRecorderOwnershipAndAccountAsText() throws {
        let app = launchFamily(memberRole: true)
        let me = "小明"
        // 家人記的家庭公帳:小美・家庭公帳、帳戶 iOS 測試存款。
        let family = try fullyVisibleRow("餐飲，晚餐-水煎包，帳戶", in: app)
        let familyText = try TextRecognition.lines(in: family.screenshot().image).joined(separator: " ")
        XCTAssertTrue(familyText.contains("小美") && familyText.contains("家庭公帳"), "家人記的列沒有「小美・家庭公帳」:\(familyText)")
        XCTAssertTrue(familyText.contains("測試存款"), "家人記的列沒有資產帳戶名稱:\(familyText)")
        // 自己記的家庭公帳也顯示自己的名稱。
        let lunch = try fullyVisibleRow("餐飲，午餐，帳戶", in: app)
        let lunchText = try TextRecognition.lines(in: lunch.screenshot().image).joined(separator: " ")
        XCTAssertTrue(lunchText.contains(me) && lunchText.contains("家庭公帳"), "自己記的家庭公帳沒有「\(me)・家庭公帳」:\(lunchText)")
        // 自己記的個人私帳,帳戶是信用卡。
        let headphones = try fullyVisibleRow("耳機", in: app)
        let headphonesText = try TextRecognition.lines(in: headphones.screenshot().image).joined(separator: " ")
        XCTAssertTrue(headphonesText.contains("個人私帳") && headphonesText.contains("測試信用卡"), "個人私帳的列不對:\(headphonesText)")
        // 系統自動產生的紀錄:記帳人換成「系統紀錄」。
        let repayment = try fullyVisibleRow("繳納【iOS 測試信用卡】卡費", in: app)
        let repaymentText = try TextRecognition.lines(in: repayment.screenshot().image).joined(separator: " ")
        XCTAssertTrue(repaymentText.contains("系統紀錄") && repaymentText.contains("家庭公帳"), "系統紀錄的列不對:\(repaymentText)")
    }

    /// 列的右邊是金額加資產帳戶(#145):兩行的右緣對齊，金額旁邊沒有舊的小圖示(分類圖示之外，第一行只有標題與金額兩群)。
    /// 預設、XXL、XXXL 都一樣是兩行。
    @MainActor
    func testRowAmountAndAccountShareTheRightEdgeWithoutOldMarkers() throws {
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryXXL", "UICTContentSizeCategoryXXXL"] {
            let app = launchFamily(memberRole: false, category: category)
            for label in ["餐飲，晚餐-水煎包，帳戶", "餐飲，午餐，帳戶"] {
                let row = try fullyVisibleRow(label, in: app)
                let image = row.screenshot().image
                let scale = Int(image.scale)
                let bands = try PixelAnalysis.inkBands(of: image, skippingLeadingCluster: true)
                XCTAssertEqual(bands.count, 2, "\(category) \(label):不是兩行(標題加次要文字):\(bands)")
                guard bands.count == 2 else { continue }
                XCTAssertEqual(bands[0].maxX, bands[1].maxX, accuracy: 3 * scale, "\(category) \(label):金額與資產帳戶右緣沒有對齊:\(bands)")
                XCTAssertEqual(bands[0].clusters(minGap: 8 * scale), 2, "\(category) \(label):第一行(圖示之後)應該只有標題與金額，金額旁邊有多的圖示:\(bands)")
                XCTAssertEqual(bands[1].clusters(minGap: 14 * scale), 2, "\(category) \(label):第二行應該是「記帳人・歸屬」加資產帳戶:\(bands)")
            }
            app.terminate()
        }
    }

    /// 無障礙字級才上下堆疊(#145):圖示加標題、記帳人・歸屬、資產帳戶由上往下，**金額在最下面一行、靠右**。
    @MainActor
    func testAccessibilityStackKeepsAmountOnTheBottomRight() throws {
        let app = launchFamily(memberRole: false, category: "UICTContentSizeCategoryAccessibilityXXXL")
        let row = try fullyVisibleRow("餐飲，晚餐-水煎包，帳戶", in: app)
        let image = row.screenshot().image
        let scale = Int(image.scale)
        let bands = try PixelAnalysis.inkBands(of: image, skippingLeadingCluster: true)
        XCTAssertGreaterThanOrEqual(bands.count, 4, "無障礙字級應該由上往下是標題、記帳人・歸屬、資產帳戶、金額:\(bands)")
        guard let amount = bands.last else { return }
        // 無障礙字級不截斷:資產帳戶、記帳人・歸屬都完整折行(辨識出來的字裡沒有「…」)。
        let recognized = try TextRecognition.lines(in: image).joined(separator: " ")
        XCTAssertFalse(recognized.contains("…") || recognized.contains("..."), "無障礙字級有字被截斷:\(recognized)")
        let rowWidth = Int(image.size.width) * scale
        XCTAssertGreaterThan(amount.minX, rowWidth / 2, "最下面一行(金額)沒有靠右:\(amount) 寬度 \(rowWidth)")
        XCTAssertEqual(amount.clusters(minGap: 14 * scale), 1, "金額那一行只該有金額:\(amount)")
        let gap = rowWidth - amount.maxX
        XCTAssertTrue(gap >= 6 * scale && gap <= 32 * scale, "金額沒有貼齊列的右內距:右邊空 \(gap) 畫素")
        // 其他行都在金額上面，而且靠左(不是金額那種靠右)。
        for band in bands.dropLast() {
            XCTAssertLessThan(band.maxY, amount.minY, "有一行在金額下面:\(band) vs \(amount)")
            XCTAssertLessThan(band.minX, rowWidth / 3, "標題、次要文字、資產帳戶應該靠左:\(band)")
        }
    }

    /// 年月快速切換(#130):上一月、下一月、選任意年月，篩選按鈕的值跟著變;本月時下一月停用。
    @MainActor
    func testMonthSwitcherChangesTheFilterRange() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        let title = app.buttons["transactions.month.title"]
        let previous = app.buttons["transactions.month.previous"]
        let next = app.buttons["transactions.month.next"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "交易頁沒有年月切換")
        XCTAssertEqual(title.value as? String, Self.taipeiMonthTitle(monthsAgo: 0), "年月不是台灣時間的本月")
        XCTAssertFalse(next.isEnabled, "本月時下一月沒有停用")
        let filter = app.buttons["transactions.filter"]
        XCTAssertEqual(filter.value as? String, "全部・\(Self.taipeiThisMonthPeriod())")

        previous.tap()
        XCTAssertEqual(title.value as? String, Self.taipeiMonthTitle(monthsAgo: 1), "上一月沒有換成上個月")
        XCTAssertTrue(next.isEnabled, "切到過去的月份後下一月還是停用")
        XCTAssertEqual(filter.value as? String, "全部・\(Self.taipeiWholeMonthPeriod(monthsAgo: 1))", "篩選按鈕的範圍沒有跟著變成整個上個月")

        next.tap()
        XCTAssertEqual(title.value as? String, Self.taipeiMonthTitle(monthsAgo: 0))
        XCTAssertEqual(filter.value as? String, "全部・\(Self.taipeiThisMonthPeriod())", "切回本月後範圍不是本月 1 號到今天")

        // 點年月選任意年月:2025 年 3 月。
        title.tap()
        let year = app.pickerWheels.element(boundBy: 0)
        let month = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(year.waitForExistence(timeout: 3), "沒有打開選年月")
        year.adjust(toPickerWheelValue: "2025年")
        month.adjust(toPickerWheelValue: "3月")
        app.buttons["transactions.month.done"].tap()
        XCTAssertEqual(title.value as? String, "2025年3月", "選了 2025年3月 但年月沒有跟著變")
        XCTAssertEqual(filter.value as? String, "全部・2025年3月1日–2025年3月31日")
    }

    /// 依帳戶篩選(上游 ADR 0019、#183):篩選 sheet 選「iOS 測試存款」，按完成後列表只剩那個帳戶的收支明細，篩選按鈕顯示套用中。
    @MainActor
    func testFilterByAccountNarrowsTheList() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()
        let card = element(in: app, labelContaining: "iOS 測試信用卡")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "範例資料裡信用卡的收支明細不在清單上")

        app.buttons["transactions.filter"].tap()
        let account = app.buttons["transactionFilter.account"]
        XCTAssertTrue(account.waitForExistence(timeout: 5), "篩選 sheet 沒有「帳戶」")
        account.tap()
        app.buttons["iOS 測試存款"].firstMatch.tap()
        app.buttons["transactionFilter.done"].tap()

        XCTAssertTrue(element(in: app, labelContaining: "午餐").waitForExistence(timeout: 5), "存款帳戶的收支明細不見了")
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "篩選了存款帳戶，信用卡的收支明細還在")
        XCTAssertTrue((app.buttons["transactions.filter"].value as? String ?? "").contains("iOS 測試存款"), "篩選按鈕的值沒有帳戶名稱")
    }

    /// 篩選 sheet 的「重設為本月」是帶圖示的列，不是看起來像標籤的純文字(#165)。
    @MainActor
    func testFilterResetRowHasAnIcon() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()
        app.buttons["transactions.filter"].tap()
        let reset = app.buttons["transactionFilter.thisMonth"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5), "篩選 sheet 沒有「重設為本月」")
        assertHasLeadingIcon(reset, "重設為本月")
    }

    /// 一列動作要有圖示:圖示在最左邊、跟文字隔一段距離，截圖裡至少有兩群墨跡。圖示是裝飾，不在 accessibility 階層裡，所以量像素。
    @MainActor
    private func assertHasLeadingIcon(_ row: XCUIElement, _ name: String) {
        let bands = try? PixelAnalysis.inkBands(of: row.screenshot().image)
        let widest = bands?.max { $0.maxX - $0.minX < $1.maxX - $1.minX }
        XCTAssertGreaterThanOrEqual(widest?.clusters(minGap: 25) ?? 0, 2, "「\(name)」只有文字，沒有圖示，看不出可以按")
    }

    /// 台灣時間往前 `monthsAgo` 個月的「2026年9月」。
    private static func taipeiMonthTitle(monthsAgo: Int) -> String {
        let (year, month) = taipeiYearMonth(monthsAgo: monthsAgo)
        return "\(year)年\(month)月"
    }

    /// 台灣時間往前 `monthsAgo` 個月的整月範圍，格式跟篩選按鈕的值一樣(同年省略年份)。
    private static func taipeiWholeMonthPeriod(monthsAgo: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let (year, month) = taipeiYearMonth(monthsAgo: monthsAgo)
        let nowYear = calendar.component(.year, from: .now)
        let days = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month, day: 1))!)!.count
        let prefix = year == nowYear ? "" : "\(year)年"
        return "\(prefix)\(month)月1日–\(prefix)\(month)月\(days)日"
    }

    private static func taipeiYearMonth(monthsAgo: Int) -> (Int, Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let date = calendar.date(byAdding: .month, value: -monthsAgo, to: .now)!
        return (calendar.component(.year, from: date), calendar.component(.month, from: date))
    }

    /// 記一筆與編輯交易共用同一份表單，欄位順序一致(#129):帳戶、日期在最上面，接著歸屬、金額、備註、分類。
    /// 以前帳戶與日期在最底下，每次都要捲到底才能選。帳戶仍然每次都是空的(上游 ADR 0011)。
    @MainActor
    func testFormFieldsStartWithAccountAndDateInQuickEntryAndEditor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        // 記一筆
        app.buttons["transactions.add"].tap()
        XCTAssertTrue(app.textFields["quickEntry.amount"].waitForExistence(timeout: 3), "沒有打開記一筆")
        assertFormOrder(in: app, context: "記一筆")
        let account = app.collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "帳戶")).firstMatch
        XCTAssertTrue(account.label.contains("請選擇"), "記一筆的帳戶不是空的:\(account.label)")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["關閉"].tap()

        // 編輯既有交易:點一筆自己的交易(午餐)
        let lunch = element(in: app, labelContaining: "餐飲，午餐，帳戶")
        for _ in 0..<8 where !(lunch.exists && lunch.isHittable) { app.swipeUp() }
        lunch.tap()
        XCTAssertTrue(app.textFields["quickEntry.amount"].waitForExistence(timeout: 3), "沒有打開編輯交易")
        assertFormOrder(in: app, context: "編輯交易")
    }

    /// 表單裡各欄位由上到下的順序:帳戶、日期、(歸屬)、金額、備註。
    @MainActor
    private func assertFormOrder(in app: XCUIApplication, context: String) {
        let form = app.collectionViews.firstMatch
        let account = form.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "帳戶")).firstMatch
        let date = form.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "日期")).firstMatch
        let amount = app.textFields["quickEntry.amount"]
        let note = app.textFields["quickEntry.note"]
        XCTAssertTrue(account.exists && date.exists && amount.exists && note.exists, "\(context):找不到欄位 帳戶\(account.exists) 日期\(date.exists) 金額\(amount.exists) 備註\(note.exists)")
        XCTAssertLessThan(account.frame.minY, date.frame.minY, "\(context):帳戶不在日期上面")
        XCTAssertLessThan(date.frame.minY, amount.frame.minY, "\(context):日期不在金額上面")
        XCTAssertLessThan(amount.frame.minY, note.frame.minY, "\(context):金額不在備註上面")
    }

    /// 數字優先的主視覺(#118):超大的淨收支，旁邊是收入與支出，下面是「支出佔收入」的比例條和每日支出長條圖;
    /// 日標頭右邊是當日淨額。範例:收入 45,000、支出 120 + 880(信用卡還款不算)。
    @MainActor
    func testHeroShowsNetIncomeExpenseRatioDailyChartAndDayNet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        let net = row("淨收支", value: "44,000 元", in: app)
        XCTAssertTrue(net.waitForExistence(timeout: 5), "沒有淨收支的大數字")
        XCTAssertGreaterThan(net.frame.height, 50, "淨收支不是大數字")
        XCTAssertTrue(row("收入", value: "45,000 元", in: app).exists, "沒有收入")
        XCTAssertTrue(row("支出", value: "1,000 元", in: app).exists, "沒有支出")
        let ratio = element(in: app, labelContaining: "支出佔收入百分之 2")
        XCTAssertTrue(ratio.exists, "沒有支出佔收入的比例條")
        XCTAssertLessThan(net.frame.minY, ratio.frame.minY, "比例條不在淨收支下面")
        // 預設區間是本月 1 號到今天:每月 1 號只有一天，一根長條不是圖，所以不顯示;2 號以後才有。
        let hasChart = Self.taipeiDayOfMonth() >= 2
        let chart = element(in: app, labelContaining: "本區間每日支出，最多的一天是")
        XCTAssertEqual(chart.exists, hasChart, "每日支出長條圖該不該顯示:今天是本月 \(Self.taipeiDayOfMonth()) 號")
        if hasChart {
            XCTAssertLessThan(ratio.frame.minY, chart.frame.minY, "長條圖不在比例條下面")
        }

        // 日標頭右邊是當日淨額。範例資料的日期相對於今天(月初時全部落在同一天)，所以這裡只確認有，
        // 數值由單元測試用固定日期驗證。日標頭在主視覺下面，還沒捲到的不在 UI 階層裡，先捲下去。
        let dayNet = element(in: app, labelContaining: "當日淨額")
        for _ in 0..<5 where !dayNet.exists { app.swipeUp() }
        XCTAssertTrue(dayNet.exists, "日標頭沒有當日淨額")
        for _ in 0..<5 where !app.buttons["transactions.filter"].isHittable { app.swipeDown() }
        // 只看收入時沒有支出，也就沒有長條圖;只看支出時收入是 0，沒有比例條，長條圖還在。
        let filter = app.buttons["transactions.filter"]
        filter.tap()
        tapRevealing(app.buttons["僅收入"], in: app)
        app.navigationBars["篩選"].buttons["完成"].tap()
        XCTAssertTrue(row("淨收支", value: "45,000 元", in: app).waitForExistence(timeout: 5), "只看收入後淨收支沒有更新")
        XCTAssertFalse(element(in: app, labelContaining: "本區間每日支出").exists, "沒有支出時還有長條圖")

        filter.tap()
        tapRevealing(app.buttons["僅支出"], in: app)
        app.navigationBars["篩選"].buttons["完成"].tap()
        XCTAssertTrue(row("淨收支", value: "負 1,000 元", in: app).waitForExistence(timeout: 5), "只看支出後淨收支沒有更新")
        XCTAssertFalse(element(in: app, labelContaining: "支出佔收入").exists, "收入是 0 時還有比例條")
        XCTAssertEqual(element(in: app, labelContaining: "本區間每日支出").exists, hasChart, "只看支出時長條圖的有無不對")
    }

    /// 收支明細列一行一個欄位(#72):VoiceOver 把整列念成一句完整的話(分類、備註、帳戶、歸屬、收支方向與金額),
    /// 自己記的不念記帳人;分組標頭是「9月28日週一」這種系統格式，不是「09/28」。
    @MainActor
    func testRowReadsAsOneSentenceAndDayHeaderUsesSystemFormat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        let lunch = app.descendants(matching: .any)["餐飲，午餐，帳戶 iOS 測試存款，家庭公帳，支出 120 元"]
        XCTAssertTrue(lunch.waitForExistence(timeout: 5), "午餐那一列沒有念成一句完整的話")
        XCTAssertTrue(
            app.staticTexts[Self.taipeiTodayHeader()].exists,
            "分組標頭不是系統格式(\(Self.taipeiTodayHeader()))"
        )
        // 範例資料都是自己記的，所以清單裡沒有任何一列念出記帳人(搜尋欄的提示也有「記帳人」,不在清單裡)。
        let list = app.collectionViews.firstMatch
        XCTAssertFalse(
            list.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "記帳人")).firstMatch.exists,
            "自己記的收支明細還顯示記帳人"
        )

        // 沒有備註的列用分類名稱，不重複念兩次。薪資在本月 1 號，在清單最下面。
        let salary = app.descendants(matching: .any)["薪資，帳戶 iOS 測試存款，家庭公帳，收入 45,000 元"]
        for _ in 0..<5 where !salary.exists { app.swipeUp() }
        XCTAssertTrue(salary.exists, "沒有備註的列沒有用分類名稱念成一句話")
    }

    /// 記一筆的支出／收入在 sheet 導覽列中間(分段控制);歸屬是表單裡一般的選擇列，表單裡沒有分段控制(#65)。
    /// 切到收入、歸屬選個人私帳，記一筆 250 元後，列表上是一筆個人私帳的收入。
    @MainActor
    func testQuickEntryTypeInNavigationBarAndOwnershipChoice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        app.buttons["transactions.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開記一筆")
        let type = app.navigationBars.segmentedControls.firstMatch
        XCTAssertTrue(type.exists, "支出／收入不在導覽列中間")
        XCTAssertTrue(type.buttons["支出"].isSelected, "記一筆預設不是支出")
        type.buttons["收入"].tap()

        let form = app.collectionViews.containing(.textField, identifier: "quickEntry.amount").firstMatch
        XCTAssertEqual(form.segmentedControls.count, 0, "記一筆的表單裡還有分段控制")
        // 歸屬是內嵌選擇列:兩列都攤開，預設選在家庭公帳，點一下就換(ADR-0004、#90)。
        XCTAssertTrue(app.buttons["家庭公帳"].isSelected, "記一筆的歸屬預設不是公帳")
        app.buttons["個人私帳"].tap()
        XCTAssertTrue(app.buttons["個人私帳"].isSelected, "點一下私帳之後沒有選起來")

        amount.tap()
        amount.typeText("250")
        app.chooseQuickEntryAccount()
        app.buttons["quickEntry.save"].tap()
        let added = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "收入 250 元", "個人私帳")
        ).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5), "記一筆後列表上沒有私帳的收入 250 元")
    }

    /// 點一筆收支明細編輯歸屬;左滑刪除(先確認);信用卡還款只有鎖定標記;搜尋只留下符合的紀錄。
    /// 編輯金額見 `testEditingAmountReplacesOriginalValue`。
    @MainActor
    func testEditDeleteRepaymentLockAndSearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        let headphones = element(in: app, labelContaining: "支出 880 元")
        XCTAssertTrue(headphones.waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, labelContaining: "個人私帳").exists)
        headphones.tap()
        let shared = app.buttons["家庭公帳"]
        XCTAssertTrue(shared.waitForExistence(timeout: 3), "編輯收支明細沒有歸屬的選項")
        XCTAssertTrue(app.buttons["個人私帳"].isSelected, "編輯的是私帳，歸屬卻沒有選在私帳")
        shared.tap()
        app.buttons["quickEntry.save"].tap()
        // 範例資料裡只有耳機是個人私帳;改成家庭公帳之後，列表上就沒有個人私帳了。
        XCTAssertTrue(element(in: app, labelContaining: "個人私帳").waitForNonExistence(timeout: 5), "編輯後歸屬沒有更新")

        // 上面有摘要，列表可能在畫面下方。iOS 26 的 tab bar 浮在內容上，被它蓋住的列 isHittable 仍然是 true,
        // 左滑卻會滑在 tab bar 上:先捲到畫面上方 3/4 以內，左滑才滑得出「刪除」。
        let lunch = element(in: app, labelContaining: "支出 120 元")
        let screenBottom = app.windows.firstMatch.frame.maxY
        for _ in 0..<5 where !(lunch.exists && lunch.frame.maxY < screenBottom * 0.75) { app.swipeUp() }
        lunch.swipeLeft()
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["確定要刪除這筆收支明細嗎？"].waitForExistence(timeout: 3), "沒有先確認就刪除")
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(lunch.waitForNonExistence(timeout: 5), "刪除後還在列表上")

        // 系統分類的收支明細點不開(#63、#146):點一下說明「系統紀錄，不能編輯或刪除」,列上沒有鎖定標記或說明文字。
        let locked = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "信用卡還款")).firstMatch
        for _ in 0..<5 where !locked.exists { app.swipeUp() }
        XCTAssertTrue(locked.exists, "信用卡還款的列不見了")
        XCTAssertFalse(locked.label.contains("系統紀錄"), "整句不該再有說明:\(locked.label)")
        locked.tap()
        let alert = app.alerts["不能編輯這筆收支明細"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3), "點信用卡還款沒有說明")
        XCTAssertTrue(alert.staticTexts["系統紀錄，不能編輯或刪除。"].exists, "說明文字不對:\(alert.debugDescription)")
        alert.buttons["好"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 3))

        // 搜尋欄在最上面，捲回去才點得到。
        let search = app.searchFields.firstMatch
        for _ in 0..<5 where !(search.exists && search.isHittable) { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("薪資")
        XCTAssertTrue(element(in: app, labelContaining: "收入 45,000 元").waitForExistence(timeout: 3))
        XCTAssertFalse(element(in: app, labelContaining: "支出 880 元").exists, "搜尋後還看得到不符合的紀錄")
    }

    /// 已經有值的金額欄，直接輸入就取代原值(#32):耳機 880 → 990 → 770。
    ///
    /// 兩條路徑都要走：表單一打開金額欄就自動取得焦點(`.task`),直接輸入;把焦點移到備註後再點金額欄。
    @MainActor
    func testEditingAmountReplacesOriginalValue() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        let headphones = element(in: app, labelContaining: "支出 880 元")
        XCTAssertTrue(headphones.waitForExistence(timeout: 5))
        headphones.tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "表單打開時金額欄沒有取得焦點")
        app.typeText("990")
        XCTAssertEqual(amount.value as? String, "990", "自動取得焦點時，輸入的數字沒有取代原值")

        // 表單變長之後(歸屬兩列、分類格)備註在鍵盤下面，不用備註欄搬焦點了:
        // 按鍵盤上的「完成」收起鍵盤、清掉焦點，再點有值的金額欄，才是「點選」這條路徑。
        app.buttons["完成"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "按完成之後鍵盤沒有收起來")
        amount.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "點金額欄之後沒有叫出鍵盤")
        amount.typeText("770")
        XCTAssertEqual(amount.value as? String, "770", "點選金額欄時，輸入的數字沒有取代原值")

        app.buttons["quickEntry.save"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "支出 770 元").waitForExistence(timeout: 5), "編輯後金額沒有更新")
    }

    /// 記一筆：焦點在備註欄時，按鍵盤上的「完成」會收起鍵盤(#61)。
    ///
    /// 以前「完成」只清掉金額欄的焦點，備註欄沒有納入同一個 focus 狀態，按了沒反應。
    @MainActor
    func testDoneOnQuickEntryNoteDismissesKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        app.buttons["transactions.add"].tap()
        let note = app.textFields["quickEntry.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "沒有打開記一筆")
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "點備註欄後沒有出現鍵盤")
        app.buttons["完成"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "備註欄按「完成」後，鍵盤沒有收起")
    }

    /// 記一筆：捲動表單會收起鍵盤(#61),表單仍然開著。
    @MainActor
    func testScrollingQuickEntryDismissesKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        app.buttons["transactions.add"].tap()
        let note = app.textFields["quickEntry.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3), "沒有打開記一筆")
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "點備註欄後沒有出現鍵盤")
        // 在鍵盤上方按住表單往上拖。`swipeUp()` 太快，表單不會開始捲動;在最上面往下拖會拉動 sheet 本身。
        let form = app.collectionViews.containing(.textField, identifier: "quickEntry.note").firstMatch
        form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "捲動表單後，鍵盤沒有收起")
        XCTAssertTrue(app.buttons["quickEntry.save"].exists, "捲動表單時把記一筆關掉了")
    }

    /// 台灣時間的今天，格式跟 DatePicker 的值一樣，例如「2026年9月28日」。
    private static func taipeiToday() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = calendar.dateComponents([.year, .month, .day], from: .now)
        return "\(day.year!)年\(day.month!)月\(day.day!)日"
    }

    /// 台灣時間今天是本月的幾號。
    private static func taipeiDayOfMonth() -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar.component(.day, from: .now)
    }

    /// 台灣時間的本月 1 號到今天，格式跟篩選按鈕的 VoiceOver 值一樣，例如「9月1日–9月28日」。
    private static func taipeiThisMonthPeriod() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = calendar.dateComponents([.month, .day], from: .now)
        return "\(day.month!)月1日–\(day.month!)月\(day.day!)日"
    }

    /// 台灣時間的今天，格式跟交易頁的分組標頭一樣，例如「9月28日週一」。
    private static func taipeiTodayHeader() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let day = calendar.dateComponents([.month, .day, .weekday], from: .now)
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        return "\(day.month!)月\(day.day!)日週\(weekdays[day.weekday! - 1])"
    }

    /// 點表單的選擇列打開選單，再點選項。sheet 底下列表的列也含有同樣的文字，所以只找選單裡的選項
    /// (直接放在 cell 裡的按鈕)。
    @MainActor
    private func choose(_ option: String, from picker: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "表單沒有這個選擇列")
        picker.tap()
        let item = app.cells.children(matching: .button)[option]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "選單裡沒有「\(option)」")
        item.tap()
    }

    /// 工具列只有篩選、記一筆、頭像三顆，沒有系統自動收成的「…」;匯出 CSV 是列表最底下的一列(ADR-0004、#86)。
    @MainActor
    func testToolbarHasThreeButtonsAndExportIsTheLastRow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["記帳"].tap()
        XCTAssertTrue(app.buttons["transactions.filter"].waitForExistence(timeout: 5), "沒有篩選按鈕")
        let toolbar = app.navigationBars.firstMatch
        for id in ["transactions.filter", "transactions.add", "toolbar.me"] {
            XCTAssertTrue(toolbar.buttons[id].exists, "工具列缺少 \(id)")
        }
        XCTAssertEqual(toolbar.buttons.count, 3, "工具列不是三顆按鈕:\(toolbar.buttonSummary)")
        XCTAssertFalse(toolbar.buttons["transactions.export"].exists, "匯出 CSV 還在工具列")

        let export = app.buttons["transactions.export"]
        for _ in 0..<12 where !(export.exists && export.isHittable) { app.swipeUp() }
        XCTAssertTrue(export.exists && export.isHittable, "列表最底下沒有「匯出 CSV」")
        XCTAssertEqual(export.label, "匯出 CSV")
    }

    /// 記一筆的「帳戶」列只顯示名稱，點了推入清單頁;清單每列有名稱與類型，選了自動返回(ADR-0004、#88)。
    @MainActor
    func testAccountIsChosenOnAPushedListPage() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["記帳"].tap()
        app.buttons["transactions.add"].tap()
        // 只在 collection view 裡找:sheet 後面底部 tab bar 也有一顆「帳戶」按鈕，但 tab bar 不是 collection view。
        // 不能用「含金額欄的 collection view」:帳戶列在 16 格分類下面，捲下去之後金額欄已被回收。
        func accountRow() -> XCUIElement {
            app.collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "帳戶")).firstMatch
        }
        // 金額欄一打開就對焦，數字鍵盤蓋住下半部;先收起鍵盤，再捲到帳戶列(在 16 格分類下面)。
        XCTAssertTrue(app.textFields["quickEntry.amount"].waitForExistence(timeout: 3), "沒有打開記一筆")
        app.buttons["完成"].tap()
        for _ in 0..<6 where !(accountRow().exists && accountRow().isHittable) { app.swipeUp() }
        XCTAssertTrue(accountRow().exists, "記一筆沒有「帳戶」列")
        // 帳戶預設是空的(上游 ADR 0011、#109):列上顯示佔位文字，不是任何一個帳戶。
        XCTAssertTrue(accountRow().displayedText.contains("請選擇扣款／存入帳戶"), "「帳戶」列沒有顯示佔位文字:\(accountRow().displayedText)")
        XCTAssertFalse(accountRow().displayedText.contains("iOS 測試存款"), "「帳戶」列預選了第一個帳戶:\(accountRow().displayedText)")

        accountRow().tap()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "iOS 測試信用卡")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3), "沒有推入帳戶清單頁")
        XCTAssertTrue(card.displayedText.contains("信用卡"), "清單頁的列沒有類型副標題:\(card.displayedText)")

        card.tap()
        XCTAssertTrue(accountRow().waitForExistence(timeout: 3), "選了帳戶之後沒有自動返回表單")
        XCTAssertTrue(accountRow().displayedText.contains("iOS 測試信用卡"), "返回之後「帳戶」列沒有顯示新選的帳戶:\(accountRow().displayedText)")
    }

    /// 記一筆沒選帳戶就儲存:被擋下並用紅字提示;選了帳戶儲存成功;再打開一次，帳戶又是空的(上游 ADR 0011、#109)。
    @MainActor
    func testQuickEntryRequiresAnAccountChoice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()

        app.buttons["transactions.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開記一筆")
        amount.tap()
        amount.typeText("300")
        app.buttons["quickEntry.save"].tap()
        XCTAssertTrue(
            element(in: app, labelContaining: "請選擇扣款或存入帳戶").waitForExistence(timeout: 3),
            "沒選帳戶就儲存，沒有顯示「請選擇扣款或存入帳戶」"
        )
        XCTAssertTrue(app.buttons["quickEntry.save"].exists, "沒選帳戶儲存時，記一筆被關掉了")

        app.chooseQuickEntryAccount("iOS 測試存款")
        app.buttons["quickEntry.save"].tap()
        XCTAssertTrue(element(in: app, labelContaining: "支出 300 元").waitForExistence(timeout: 5), "選了帳戶儲存後沒有出現在列表上")

        // 再打開一次:帳戶又是空的(不沿用上一筆)。
        app.buttons["transactions.add"].tap()
        XCTAssertTrue(app.textFields["quickEntry.amount"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        let row = app.collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "帳戶")).firstMatch
        for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.displayedText.contains("請選擇扣款／存入帳戶"), "再打開記一筆，帳戶沒有清成空的:\(row.displayedText)")
    }

    /// 分類攤開成格，點一下就選;切到收入換成收入的分類;選了「交通」記一筆，列表上是交通(ADR-0004、#89)。
    @MainActor
    func testCategoryIsChosenInAGridWithOneTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSession"]
        app.launch()
        signIn(app)

        app.tabBars.buttons["記帳"].tap()
        app.buttons["transactions.add"].tap()
        let amount = app.textFields["quickEntry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 3), "沒有打開記一筆")

        XCTAssertTrue(app.buttons["餐飲"].waitForExistence(timeout: 5), "分類不是攤開的格子")
        XCTAssertTrue(app.buttons["餐飲"].isSelected, "預設分類不是餐飲")
        for name in ["交通", "娛樂", "購物", "生活", "醫療", "教育", "其他"] {
            XCTAssertTrue(app.buttons[name].exists, "分類格缺少「\(name)」")
        }
        app.buttons["交通"].tap()
        XCTAssertTrue(app.buttons["交通"].isSelected, "點一下之後交通沒有被選起來")
        XCTAssertFalse(app.buttons["餐飲"].isSelected, "選了交通，餐飲還是選取狀態")

        let type = app.navigationBars.segmentedControls.firstMatch
        type.buttons["收入"].tap()
        for name in ["薪資", "獎金", "投資", "兼職"] {
            XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3), "收入的分類格缺少「\(name)」")
        }
        XCTAssertFalse(app.buttons["餐飲"].exists, "切到收入之後還看得到支出的分類")
        type.buttons["支出"].tap()
        XCTAssertTrue(app.buttons["餐飲"].waitForExistence(timeout: 3))
        app.buttons["交通"].tap()

        amount.tap()
        amount.typeText("88")
        app.chooseQuickEntryAccount()
        app.buttons["quickEntry.save"].tap()
        let added = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "交通", "支出 88 元")
        ).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5), "記一筆後列表上沒有交通的支出 88 元")
    }

    /// 篩選 sheet 是 medium 高度時，下半部的列還沒被建出來：捲到點得到為止再點。
    @MainActor
    private func tapRevealing(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !(element.exists && element.isHittable) { app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, "捲動之後還是點不到「\(element.label)」")
        element.tap()
    }

    @MainActor
    private func row(_ label: String, value: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", label, value)).firstMatch
    }

    @MainActor
    private func element(in app: XCUIApplication, labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// 家庭管理員或一般成員登入，有家人(小美)記的交易。
    @MainActor
    private func launchFamily(memberRole: Bool, category: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingJoinedHousehold", "-uiTestingFamilyEntries", "-resetSession"]
            + (memberRole ? ["-uiTestingMemberRole"] : [])
            + (category.map { ["-UIPreferredContentSizeCategoryName", $0] } ?? [])
        app.launch()
        signIn(app)
        app.tabBars.buttons["記帳"].tap()
        return app
    }

    /// 捲到整列都在畫面上(不被 tab bar 或導覽列蓋住)，才截圖分析。
    @MainActor
    private func fullyVisibleRow(_ labelContaining: String, in app: XCUIApplication) throws -> XCUIElement {
        let row = element(in: app, labelContaining: labelContaining)
        XCTAssertTrue(ScrollSupport.revealFully(row, in: app), "捲不到整列都看得到:\(labelContaining) \(row.frame)")
        return row
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
