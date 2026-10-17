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
        ).makeStatementRollover(locale: Locale(identifier: "zh_Hant_TW"))
    }

    @Test("打開時載入預覽:延期的集合是開窗時已延至下期的明細;上期延入款預設納入本期(不在延期裡)")
    func loadStartsFromTheBackendDeferrals() async {
        let model = model()
        #expect(model.outlook == nil, "還沒載入")

        await model.load()

        #expect(model.items.map(\.note) == ["本期延期", "本期刷退", "本期午餐", "家庭晚餐", "家庭交通", "上期延入"])
        #expect(model.isDeferred(deferred))
        #expect(!model.isDeferred(prior), "上期延入款首次結算預設納入")
        #expect(!model.isDeferred(lunch))
        #expect(model.deferredCount == 1)
    }

    @Test("試算:維持開窗時的延期，出帳淨額 2,400、出帳後待繳 14,400(12,000 + 2,400)、剩餘未出帳 1,100(300 + 800);公帳 600、私帳 1,800")
    func outlookAtOpen() async throws {
        let model = model()
        await model.load()

        let outlook = try #require(model.outlook)
        #expect(outlook.net == Money(2400))
        #expect(outlook.projectedBilled == Money(14400))
        #expect(outlook.projectedUnbilled == Money(1100))
        #expect(outlook.sharedDebt == Money(600), "只有待報銷的公帳;家庭交通已由家庭報銷，轉列私帳")
        #expect(outlook.personalDebt == Money(1800))
    }

    @Test("四層摘要:本期新增 2,700、本期延後 800、上期延入 500，恆等式成立;剩餘未出帳 2 筆(結帳日之後 1 筆 + 延後 1 筆)")
    func sourceLayers() async throws {
        let model = model()
        await model.load()

        let outlook = try #require(model.outlook)
        #expect(outlook.newInCycle == Money(2700))
        #expect(outlook.newInCycleCount == 5)
        #expect(outlook.deferred == Money(800))
        #expect(outlook.deferredCount == 1)
        #expect(outlook.priorIncoming == Money(500))
        #expect(outlook.priorIncomingCount == 1)
        #expect(outlook.newInCycle - outlook.deferred + outlook.priorIncoming == outlook.net)
        #expect(outlook.remainingUnbilledCount == 2)
    }

    @Test("切換「延至下期」:就地重算，不呼叫出帳;再切回來恢復")
    func togglingRecomputesLocally() async throws {
        let repository = InMemoryAccountRepository.sample()
        let model = model(repository: repository)
        await model.load()

        model.toggleDeferral(lunch)
        #expect(model.isDeferred(lunch))
        #expect(try #require(model.outlook).net == Money(1200))
        #expect(try #require(model.outlook).projectedUnbilled == Money(2300))

        model.toggleDeferral(lunch)
        #expect(!model.isDeferred(lunch))
        #expect(try #require(model.outlook).net == Money(2400))
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

    @Test("結算區間:後端算好的起訖日;結帳日已過說明結算本期帳單，還沒到說明結算上一期帳單")
    func period() async {
        let model = model()
        await model.load()
        #expect(model.periodText == "9月16日 ～ 10月15日")
        #expect(model.periodNote == "結算本期帳單")

        let pending = StatementPreview(
            startDate: CalendarDay(year: 2026, month: 8, day: 26), endDate: CalendarDay(year: 2026, month: 9, day: 25),
            isStatementPending: true, items: [], baseNetBilled: .zero, totalRepay: .zero, baseNetUnbilled: .zero
        )
        let repository = InMemoryAccountRepository(
            accounts: SampleAccounts.all, summary: SampleAccounts.summary, statementPreviews: [SampleAccounts.card.id: pending]
        )
        let early = self.model(repository: repository)
        await early.load()
        #expect(early.periodText == "8月26日 ～ 9月25日")
        #expect(early.periodNote == "結帳日還沒到，結算上一期帳單")
    }

    @Test("沒設結帳日的卡:後端拒絕出帳預覽，顯示後端的訊息")
    func cardWithoutStatementDay() async {
        let bare = CreditCard(
            id: AccountID("bare"), name: "無結帳日卡", colorHex: "#FFD4A0", billedDebt: Money(100), unbilledDebt: .zero,
            creditLimit: nil, statementDay: nil, paymentDueDay: nil
        )
        let repository = InMemoryAccountRepository(accounts: [.creditCard(bare)], summary: SampleAccounts.summary)
        let model = model(bare, repository: repository)

        await model.load()

        #expect(model.errorMessage == "此信用卡尚未設定每月結帳日，請先至帳戶設定填寫結帳日方可進行出帳作業")
        #expect(!model.canConfirm)
    }

    @Test("上期延入款的提示:有上期延入款而且這一期還沒出過帳才顯示")
    func priorDeferredNote() async {
        let model = model()
        await model.load()
        #expect(model.priorDeferredNote == "含 1 筆上期延入款，已預設納入本期")
    }

    @Test("明細的說明:日期，上期延入款與公帳的家庭報銷狀態加標記")
    func itemDetailText() async throws {
        let model = model()
        await model.load()

        let priorItem = try #require(model.items.first { $0.id == prior })
        let lunchItem = try #require(model.items.first { $0.id == lunch })
        let dinnerItem = try #require(model.items.first { $0.note == "家庭晚餐" })
        let trafficItem = try #require(model.items.first { $0.note == "家庭交通" })
        #expect(model.itemDetailText(priorItem) == "9月10日 · 上期延入")
        #expect(model.itemDetailText(lunchItem) == "10月10日")
        #expect(model.itemDetailText(dinnerItem) == "10月9日 · 公帳・待報銷")
        #expect(model.itemDetailText(trafficItem) == "10月8日 · 公帳・家庭已報銷")
    }
}
