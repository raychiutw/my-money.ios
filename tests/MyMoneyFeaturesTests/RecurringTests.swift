import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("週期收支")
struct RecurringTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func loaded(dataVersion: DataVersion = DataVersion()) async -> (RecurringModel, InMemoryRecurringRepository) {
        let repository = InMemoryRecurringRepository.sample()
        let model = RecurringModel(
            repository: repository,
            accounts: InMemoryAccountRepository.sample(),
            dataVersion: dataVersion,
            today: { today }
        )
        await model.load()
        return (model, repository)
    }

    @Test("週期支出與週期收入分成兩區")
    func splitsByType() async {
        let (model, _) = await loaded()

        #expect(model.expenses.map(\.name) == ["房租", "年繳保費"])
        #expect(model.incomes.map(\.name) == ["薪水"])
    }

    @Test("三張統計卡：週期支出與週期收入的分攤平滑(後端算好)、每月週期淨額")
    func summaryCards() async {
        let (model, _) = await loaded()

        #expect(model.monthlyExpense == Money(14000))
        #expect(model.monthlyIncome == Money(45000))
        #expect(model.monthlyNet == Money(31000))
    }

    /// 上游 `feabed3` 起 web 的 `formatScheduleLabel` 寫出確切時程;收入寫「入帳」、支出寫「扣款」(#131)。
    @Test("確切時程標籤:月繳、單數月／雙數月、每季、每半年、每年", arguments: [
        (RecurringCycle.monthly, 1, TransactionType.expense, 5, "每月 5 號扣款"),
        (.monthly, 1, .income, 25, "每月 25 號入帳"),
        (.bimonthly, 1, .expense, 10, "單數月 10 號扣款"),
        (.bimonthly, 2, .income, 10, "雙數月 10 號入帳"),
        (.quarterly, 1, .expense, 5, "每季 (1/4/7/10月) 5 號扣款"),
        (.quarterly, 2, .expense, 5, "每季 (2/5/8/11月) 5 號扣款"),
        (.quarterly, 3, .income, 5, "每季 (3/6/9/12月) 5 號入帳"),
        (.semiannual, 1, .expense, 1, "每半年 (1/7月) 1 號扣款"),
        (.semiannual, 6, .income, 1, "每半年 (6/12月) 1 號入帳"),
        (.annual, 5, .expense, 15, "每年 5 月 15 號扣款"),
        (.annual, 12, .income, 25, "每年 12 月 25 號入帳"),
        // 月份超出這個週期的範圍(例如別的 client 改了週期)時，標籤與編輯器存的值都用修正後的月份。
        (.bimonthly, 3, .expense, 10, "單數月 10 號扣款"),
        (.quarterly, 7, .expense, 5, "每季 (1/4/7/10月) 5 號扣款"),
    ])
    func scheduleText(cycle: RecurringCycle, month: Int, type: TransactionType, day: Int, expected: String) {
        let item = RecurringItem(
            id: RecurringItemID("x"), name: "x", type: type, amount: Money(1200), cycle: cycle, dayOfCycle: day,
            monthOfCycle: month, accountID: nil, accountName: nil
        )

        #expect(item.scheduleText == expected)
    }

    @Test("舊資料沒有繳費月份時(預設 1)，季繳是 1/4/7/10 月、年繳是 1 月")
    func defaultMonthIsOne() {
        let quarterly = RecurringItem(
            id: RecurringItemID("x"), name: "x", type: .expense, amount: Money(1), cycle: .quarterly, dayOfCycle: 5,
            accountID: nil, accountName: nil
        )
        #expect(quarterly.monthOfCycle == 1)
        #expect(quarterly.scheduleText == "每季 (1/4/7/10月) 5 號扣款")
    }

    @Test("週期不是每月的週期支出，顯示每月的分攤平滑;週期收入不顯示")
    func perItemAmortization() {
        let annual = RecurringItem(
            id: RecurringItemID("x"), name: "年繳保費", type: .expense, amount: Money(24000), cycle: .annual,
            dayOfCycle: 15, accountID: nil, accountName: nil
        )
        let monthly = RecurringItem(
            id: RecurringItemID("y"), name: "房租", type: .expense, amount: Money(12000), cycle: .monthly,
            dayOfCycle: 5, accountID: nil, accountName: nil
        )
        let annualIncome = RecurringItem(
            id: RecurringItemID("z"), name: "年終獎金", type: .income, amount: Money(60000), cycle: .annual,
            dayOfCycle: 20, accountID: nil, accountName: nil
        )

        #expect(annual.monthlyAmortization == Money(2000))
        #expect(annual.showsMonthlyAmortization)
        #expect(!monthly.showsMonthlyAmortization)
        #expect(!annualIncome.showsMonthlyAmortization)
    }

    /// 一行一個欄位(DESIGN.md「列與欄位」,#77):帳戶不加前綴、沒設就不顯示;分攤平滑單獨寫成「$2,000／月」。
    @Test("列的文字：帳戶不加前綴、沒設就不顯示，非每月的週期支出顯示每月分攤平滑，VoiceOver 念成一句")
    func rowTexts() {
        let annual = RecurringItem(
            id: RecurringItemID("x"), name: "年繳保費", type: .expense, amount: Money(24000), cycle: .annual,
            dayOfCycle: 15, accountID: nil, accountName: nil
        )
        let rent = RecurringItem(
            id: RecurringItemID("y"), name: "房租", type: .expense, amount: Money(12000), cycle: .monthly,
            dayOfCycle: 5, accountID: AccountID("a"), accountName: "iOS 測試存款"
        )
        let salary = RecurringItem(
            id: RecurringItemID("z"), name: "薪水", type: .income, amount: Money(45000), cycle: .monthly,
            dayOfCycle: 25, accountID: AccountID("a"), accountName: "iOS 測試存款"
        )

        #expect(annual.accountText == nil)
        #expect(rent.accountText == "iOS 測試存款")
        #expect(annual.amortizationText == "$2,000／月")
        #expect(rent.amortizationText == nil)
        #expect(salary.amortizationText == nil)
        #expect(annual.spokenText == "年繳保費，週期支出 24,000 元，每年 1 月 15 號扣款，個人私帳，分攤平滑每月 2,000 元")
        #expect(rent.spokenText == "房租，週期支出 12,000 元，每月 5 號扣款，個人私帳，帳戶 iOS 測試存款")
        #expect(salary.spokenText == "薪水，週期收入 45,000 元，每月 25 號入帳，個人私帳，帳戶 iOS 測試存款")
    }

    @Test("刪除後資料版本遞增;確認文字包含名稱")
    func deleteBumpsDataVersion() async throws {
        let dataVersion = DataVersion()
        let (model, repository) = await loaded(dataVersion: dataVersion)
        let rent = try #require(model.expenses.first)

        #expect(model.deleteConfirmation(for: rent) == "確定要刪除週期收支「房租」嗎？")
        await model.delete(rent)

        #expect(await repository.deletedIDs == [rent.id])
        #expect(dataVersion.value == 1)
    }

    @Test("匯出 CSV 的檔名跟 web 一樣")
    func csvFileName() async throws {
        let (model, _) = await loaded()

        let export = model.csvExport()

        #expect(export.fileName == "recurring-2026-09-28.csv")
        #expect(try await export.fetch() == InMemoryRecurringRepository.sampleCSV)
    }

    /// web 把失敗當成 0,三張統計卡顯示 $0(`.catch(() => null)`,parity 刻意偏離第 27 項)。
    @Test("分攤平滑載入失敗時顯示載入失敗，不顯示 $0")
    func amortizationFailure() async {
        let repository = InMemoryRecurringRepository.sample()
        await repository.failAmortization(with: .rejected("伺服器錯誤"))
        let model = RecurringModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(), dataVersion: DataVersion(),
            today: { today }
        )

        await model.load()

        #expect(model.phase == .failed("伺服器錯誤"))
    }

    @Test("資料版本改變後重抓")
    func refreshesOnDataVersionChange() async {
        let dataVersion = DataVersion()
        let (model, repository) = await loaded(dataVersion: dataVersion)
        let fetches = await repository.fetchCount

        await model.refreshIfStale()
        #expect(await repository.fetchCount == fetches)

        dataVersion.bump()
        await model.refreshIfStale()
        #expect(await repository.fetchCount > fetches)
    }

    // MARK: 視角、建立者・歸屬、權限(上游 ADR 0016、#152)

    private let me = UserID("in-memory-member-1")
    private let mei = UserID("sample-mei")

    private func scoped(
        role: HouseholdRole? = .admin, defaults: UserDefaults? = nil, gate: Gate? = nil
    ) async -> (RecurringModel, InMemoryRecurringRepository) {
        let repository = InMemoryRecurringRepository(items: InMemoryRecurringRepository.sampleItems + [InMemoryRecurringRepository.meiInternet], currentUser: me, gate: gate)
        let model = RecurringModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(), dataVersion: DataVersion(),
            permissions: PermissionsModel(userID: me, role: role),
            defaults: defaults ?? UserDefaults(suiteName: "RecurringTests.\(UUID().uuidString)")!, today: { today }
        )
        return (model, repository)
    }

    @Test("視角預設是全部;選過的視角記在 UserDefaults，下次沿用")
    func scopeIsRemembered() async {
        let suite = "RecurringTests.remember.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (first, _) = await scoped(defaults: defaults)
        #expect(first.scope == .all)

        first.scope = .household
        let (second, _) = await scoped(defaults: defaults)

        #expect(second.scope == .household)
    }

    @Test("載入時一律明確帶視角(全部也帶);列表與分攤平滑都依視角")
    func loadsWithScope() async {
        let (model, repository) = await scoped()

        await model.load()
        #expect(await repository.requestedItemScopes == [.all])
        #expect(await repository.requestedAmortizationScopes == [.all])
        #expect(model.items.map(\.name) == ["房租", "年繳保費", "薪水", "網路費"], "全部 = 自己的加上家人的家庭公帳")

        model.scope = .household
        await model.load()
        #expect(model.items.map(\.name) == ["房租", "網路費"], "家庭公帳 = 全家人的家庭公帳項目")
        #expect(model.monthlyExpense == Money(12000 + 899))

        model.scope = .personal
        await model.load()
        #expect(model.items.map(\.name) == ["年繳保費", "薪水"], "個人私帳 = 我建立的個人私帳項目")
        #expect(model.monthlyExpense == Money(2000))
        #expect(await repository.requestedItemScopes == [.all, .household, .personal])
    }

    @Test("換了視角之後才回來的舊視角回應不蓋掉畫面", .timeLimit(.minutes(1)))
    func staleScopeResponseIsDropped() async {
        let gate = Gate()
        let (model, _) = await scoped(gate: gate)

        let loading = Task { await model.load() }
        await gate.waitUntilReached()
        model.scope = .personal
        await gate.open()
        await loading.value

        #expect(model.items.isEmpty, "全部視角的舊回應不該套用到個人私帳")
        #expect(model.phase == .loading)
    }

    @Test("每一項顯示「建立者・歸屬」:自己建立的也顯示")
    func ownerText() async {
        let (model, _) = await scoped()
        await model.load()

        let byName = Dictionary(uniqueKeysWithValues: model.items.map { ($0.name, $0) })
        #expect(byName["房租"]?.ownerText == "小明・家庭公帳")
        #expect(byName["年繳保費"]?.ownerText == "小明・個人私帳")
        #expect(byName["網路費"]?.ownerText == "小美・家庭公帳")
        #expect(byName["網路費"]?.spokenText.contains("建立者 小美，家庭公帳") == true)
    }

    @Test("誰能改:個人私帳只有建立者;家庭公帳是建立者或家庭管理員;不能改的有說明與提示")
    func modification() async throws {
        let cases: [(HouseholdRole?, Bool)] = [(.member, false), (.admin, true), (nil, false)]
        for (role, mayEditMei) in cases {
            let (model, _) = await scoped(role: role)
            await model.load()
            let rent = try #require(model.items.first { $0.name == "房租" })
            let internet = try #require(model.items.first { $0.name == "網路費" })

            #expect(model.canModify(rent), "自己建立的永遠能改")
            #expect(model.lockReason(for: rent) == nil && model.lockHint(for: rent) == nil)
            #expect(model.canModify(internet) == mayEditMei, "他人建立的家庭公帳:只有家庭管理員能改(\(String(describing: role)))")
            if !mayEditMei {
                #expect(model.lockReason(for: internet) == "他人建立的家庭公帳，僅建立者或家庭管理員可以編輯、刪除")
                #expect(model.lockHint(for: internet) == "點兩下查看為什麼不能編輯")
            }
        }
        let (model, _) = await scoped()
        #expect(model.lockAlertTitle == "不能編輯這個週期收支")
    }
}
