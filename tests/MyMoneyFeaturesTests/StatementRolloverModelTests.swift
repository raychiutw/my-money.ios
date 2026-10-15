import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("出帳預覽與出帳作業(上游 ADR 0024)")
struct StatementRolloverModelTests {
    private let dataVersion = DataVersion()
    private let today = CalendarDay(year: 2026, month: 10, day: 16)
    private let deferred = TransactionID("sample-stmt-deferred")
    private let lunch = TransactionID("sample-stmt-lunch")
    private let prior = TransactionID("sample-stmt-prior")

    private func model(
        _ card: CreditCard = SampleAccounts.card, repository: InMemoryAccountRepository = .sample()
    ) -> StatementRolloverModel {
        CreditCardDetailModel(
            card: card, bankAccounts: [SampleAccounts.savings], loadedVersion: dataVersion.value, scope: .all,
            repository: repository, dataVersion: dataVersion, today: { today }
        ).makeStatementRollover()
    }

    @Test("打開時載入預覽:延期的集合是開窗時已延至下期的明細;上期延入款預設納入本期(不在延期裡)")
    func loadStartsFromTheBackendDeferrals() async {
        let model = model()
        #expect(model.outlook == nil, "還沒載入")

        await model.load()

        #expect(model.items.map(\.note) == ["本期延期", "本期刷退", "本期午餐", "上期延入"])
        #expect(model.isDeferred(deferred))
        #expect(!model.isDeferred(prior), "上期延入款首次結算預設納入")
        #expect(!model.isDeferred(lunch))
        #expect(model.deferredCount == 1)
    }

    @Test("試算:維持開窗時的延期，出帳淨額 1,400、出帳後待繳 13,400(12,000 + 1,400)、剩餘未出帳 2,100(1,300 + 800)")
    func outlookAtOpen() async throws {
        let model = model()
        await model.load()

        let outlook = try #require(model.outlook)
        #expect(outlook.net == Money(1400))
        #expect(outlook.projectedBilled == Money(13400))
        #expect(outlook.projectedUnbilled == Money(2100))
    }

    @Test("切換「延至下期」:就地重算，不呼叫出帳;再切回來恢復")
    func togglingRecomputesLocally() async throws {
        let repository = InMemoryAccountRepository.sample()
        let model = model(repository: repository)
        await model.load()

        model.toggleDeferral(lunch)
        #expect(model.isDeferred(lunch))
        #expect(try #require(model.outlook).net == Money(200))
        #expect(try #require(model.outlook).projectedUnbilled == Money(3300))

        model.toggleDeferral(lunch)
        #expect(!model.isDeferred(lunch))
        #expect(try #require(model.outlook).net == Money(1400))
        #expect(await repository.rolledOverIDs.isEmpty, "切換只在本地，確認才送出")
    }

    @Test("再載入一次(從別的頁返回、.task 重跑)不會把使用者切換過的延期洗掉")
    func reloadKeepsTheUsersChoices() async {
        let model = model()
        await model.load()
        model.toggleDeferral(lunch)

        await model.load()

        #expect(model.isDeferred(lunch))
    }

    @Test("確認出帳:送出目前選的延期明細，顯示後端的訊息，資料版本遞增")
    func confirm() async throws {
        let repository = InMemoryAccountRepository.sample()
        let model = model(repository: repository)
        await model.load()
        model.toggleDeferral(lunch)

        let message = await model.submit()

        #expect(await repository.rolledOverIDs == [SampleAccounts.card.id])
        #expect(await repository.rolledOverDeferrals == [[deferred, lunch]])
        #expect(message?.hasPrefix("帳單出帳作業完成！") == true)
        #expect(dataVersion.value == 1)
        #expect(model.errorMessage == nil)
    }

    @Test("載入完成前不能確認")
    func confirmIsDisabledWhileLoading() async {
        let gate = Gate()
        let model = model(repository: .sample(gate: gate))
        #expect(!model.canConfirm, "還沒載入")

        let loading = Task { await model.load() }
        await gate.waitUntilReached()
        #expect(!model.canConfirm, "載入中")
        await gate.open()
        await loading.value

        #expect(model.canConfirm)
    }

    @Test("送出期間 isSaving 為真、停用確認;完成後恢復")
    func savingState() async {
        let gate = Gate()
        let model = model(repository: .sample(gate: gate))

        let saving = Task { await model.submit() }
        await gate.waitUntilReached()
        #expect(model.isSaving)
        await gate.open()
        _ = await saving.value

        #expect(!model.isSaving)
    }

    @Test("這一期沒有任何刷卡記錄:後端拒絕，顯示原文，資料版本不變")
    func emptyCycleIsRejected() async {
        let repository = InMemoryAccountRepository(accounts: SampleAccounts.all, summary: SampleAccounts.summary)
        let model = model(repository: repository)
        await model.load()

        let message = await model.submit()

        #expect(message == nil)
        #expect(model.errorMessage == "目前結帳週期內無任何刷卡記錄")
        #expect(dataVersion.value == 0)
    }

    @Test("載入完了但這一期沒有任何明細:標示為空，不能確認")
    func emptyCycleCannotBeConfirmed() async {
        let repository = InMemoryAccountRepository(accounts: SampleAccounts.all, summary: SampleAccounts.summary)
        let model = model(repository: repository)
        await model.load()

        #expect(model.isEmptyCycle)
        #expect(!model.canConfirm)
    }

    @Test("載入失敗:顯示錯誤，不能確認;之後可以重新載入")
    func loadFailure() async {
        let repository = InMemoryAccountRepository.sample()
        await repository.fail(with: .rejected("信用卡不存在"))
        let model = model(repository: repository)

        await model.load()

        #expect(model.errorMessage == "信用卡不存在")
        #expect(!model.canConfirm)
        #expect(model.outlook == nil)
    }

    @Test("結算區間:上一個結帳日的次日到這一期的結帳日;沒有結帳日的卡說明「所有未出帳的消費」")
    func periodText() async {
        let withDay = model()
        await withDay.load()
        #expect(withDay.periodText == "9月16日 ～ 10月15日")

        let repository = InMemoryAccountRepository(accounts: SampleAccounts.all, summary: SampleAccounts.summary)
        let withoutDay = model(repository: repository)
        await withoutDay.load()
        #expect(withoutDay.periodText == "所有未出帳的消費")
    }

    @Test("上期延入款的提示:有上期延入款而且這一期還沒出過帳才顯示")
    func priorDeferredNote() async {
        let model = model()
        await model.load()
        #expect(model.priorDeferredNote == "含 1 筆上期延入款，已預設納入本期")
    }

    @Test("明細的說明:日期，上期延入款加標記")
    func itemDetailText() async throws {
        let model = model()
        await model.load()

        let priorItem = try #require(model.items.first { $0.id == prior })
        let lunchItem = try #require(model.items.first { $0.id == lunch })
        #expect(model.itemDetailText(priorItem) == "9月10日 · 上期延入")
        #expect(model.itemDetailText(lunchItem) == "10月10日")
    }
}
