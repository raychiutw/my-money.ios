import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 公帳範圍的私卡代墊(上游 ADR 0015、#139):家人用個人信用卡替家庭墊付的欠款，在公帳範圍看得到;他人的卡經過脫敏。
@MainActor
@Suite("私卡代墊")
struct PrivateCardAdvanceTests {
    private let me = InMemoryAuthRepository.Member.sample.user.id
    private let dataVersion = DataVersion()

    private func accountsModel(scope: AccountScope, role: HouseholdRole? = .member) async -> AccountsModel {
        let repository = InMemoryAccountRepository(
            accounts: SampleAccounts.all + [.creditCard(SampleAccounts.meiCardAdvance), .bank(SampleAccounts.meiJointFund)],
            summary: SampleAccounts.summary
        )
        let model = AccountsModel(
            repository: repository, dataVersion: dataVersion, permissions: PermissionsModel(userID: me, role: role)
        )
        model.scope = scope
        await model.load()
        return model
    }

    @Test("公帳範圍有家人的私卡代墊與自己有家庭代墊的私卡;全部範圍照舊;私帳範圍沒有脫敏的卡")
    func householdScopeListsPrivateCardsWithSharedDebt() async {
        let household = await accountsModel(scope: .household)
        #expect(household.creditCards.map(\.name).sorted() == ["iOS 測試信用卡", "小美的信用卡"].sorted(),
                "有家庭代墊的私卡才會出現(小額卡沒有)")

        let all = await accountsModel(scope: .all)
        #expect(all.creditCards.map(\.name).sorted() == ["iOS 測試信用卡", "iOS 測試小額卡"].sorted(), "他人的私卡只在公帳範圍")
    }

    @Test("卡片小字:公帳範圍的個人卡寫「私卡代墊」加繳款日;其他範圍照舊寫家庭公帳或個人私帳")
    func captions() async {
        let household = await accountsModel(scope: .household)
        #expect(household.caption(for: SampleAccounts.meiCardAdvance) == "私卡代墊・25 日繳")
        #expect(household.caption(for: SampleAccounts.card) == "私卡代墊・5 日繳", "自己的私卡在公帳範圍也標私卡代墊")

        let all = await accountsModel(scope: .all)
        #expect(all.caption(for: SampleAccounts.card) == "個人私帳・5 日繳")
    }

    @Test("切換範圍重新載入期間畫面還是舊內容:小字與念法跟著已載入的內容走，不跟著新範圍(code review)")
    func captionsFollowTheLoadedContent() async {
        let model = await accountsModel(scope: .household)
        #expect(model.caption(for: SampleAccounts.meiCardAdvance) == "私卡代墊・25 日繳")

        model.scope = .all // 還沒重新載入，畫面上仍是公帳範圍的卡
        #expect(model.caption(for: SampleAccounts.meiCardAdvance) == "私卡代墊・25 日繳")
        #expect(model.spokenSummary(of: SampleAccounts.meiCardAdvance).contains("私卡代墊"))

        await model.load()
        #expect(model.caption(for: SampleAccounts.card) == "個人私帳・5 日繳")
    }

    @Test("總覽的公帳視角:私卡代墊的卡念私卡代墊，脫敏的卡念持卡人與家庭代墊待繳額;全部視角照舊")
    func overviewCards() async {
        let suite = "PrivateCardAdvanceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let today = CalendarDay(year: 2026, month: 10, day: 3)
        let overview = OverviewModel(
            accounts: InMemoryAccountRepository(
                accounts: SampleAccounts.all + [.creditCard(SampleAccounts.meiCardAdvance)], summary: SampleAccounts.summary
            ),
            transactions: InMemoryTransactionRepository(transactions: []),
            statistics: InMemoryStatisticsRepository.sample(month: CalendarMonth(today)),
            goals: InMemorySavingsGoalRepository.sample(), dataVersion: dataVersion,
            permissions: PermissionsModel(userID: me, role: .member), defaults: defaults, today: { today },
            locale: Locale(identifier: "zh_Hant_TW")
        )
        overview.scope = .household
        await overview.load()

        let mei = overview.accountCards.first { $0.id == SampleAccounts.meiCardAdvance.id }
        #expect(mei?.amount == Money(1200), "金額是家庭代墊待繳額")
        #expect(mei?.spokenText == "小美的信用卡，私卡代墊，持卡人 小美，家庭代墊待繳額 1,200 元，每月 25 日繳款")
        let own = overview.accountCards.first { $0.id == SampleAccounts.card.id }
        #expect(own?.spokenText.hasPrefix("iOS 測試信用卡，私卡代墊，信用卡待繳總額") == true)

        overview.scope = .all
        await overview.load()
        let ownInAll = overview.accountCards.first { $0.id == SampleAccounts.card.id }
        #expect(ownInAll?.spokenText == "iOS 測試信用卡，個人私帳，信用卡待繳總額 15,500 元，代墊 3,000 元，私帳 12,500 元，未出帳 3,500 元，每月 5 日繳款")
        #expect(overview.accountCards.contains { $0.id == SampleAccounts.meiCardAdvance.id } == false, "他人的私卡只在公帳視角")
    }

    @Test("VoiceOver:脫敏的卡念私卡代墊、持卡人與家庭代墊待繳額，不念被遮蔽的欄位")
    func maskedSpokenSummary() async {
        let household = await accountsModel(scope: .household)

        #expect(
            household.spokenSummary(of: SampleAccounts.meiCardAdvance)
                == "小美的信用卡，私卡代墊，持卡人 小美，家庭代墊待繳額 1,200 元，每月 25 日繳款"
        )
        #expect(household.spokenSummary(of: SampleAccounts.card).hasPrefix("iOS 測試信用卡，私卡代墊，信用卡待繳總額"))

        let all = await accountsModel(scope: .all)
        #expect(all.spokenSummary(of: SampleAccounts.card) == "iOS 測試信用卡，個人私帳，信用卡待繳總額 15,500 元，每月 5 日繳款")
    }

    @Test("他人的卡是脫敏的:後端標了 is_masked;自己的卡與家庭卡不是")
    func isMasked() async {
        let model = await accountsModel(scope: .household)

        #expect(model.isMasked(SampleAccounts.meiCardAdvance))
        #expect(!model.isMasked(SampleAccounts.card))
    }

    // MARK: 詳細頁

    private func detail(_ card: CreditCard, role: HouseholdRole? = .member) -> CreditCardDetailModel {
        CreditCardDetailModel(
            card: card, bankAccounts: [SampleAccounts.savings], loadedVersion: dataVersion.value, scope: .household,
            repository: InMemoryAccountRepository.sample(), dataVersion: dataVersion,
            permissions: PermissionsModel(userID: me, role: role), today: { CalendarDay(year: 2026, month: 10, day: 3) }
        )
    }

    @Test("脫敏的卡詳細頁:卡費只有家庭代墊，個人帳單與個人消費顯示「隱私遮蔽」，沒有額度與剩餘額度")
    func maskedDetailRows() {
        let model = detail(SampleAccounts.meiCardAdvance)

        #expect(model.isMasked)
        #expect(model.feeRows.map(\.title) == ["家庭公帳代墊待繳總額", "個人帳單狀態", "公帳代墊待清償", "個人私帳消費"])
        #expect(model.feeRows.map(\.value) == ["$1,200", "隱私遮蔽", "$1,200", "隱私遮蔽"])
        #expect(model.limitRows.isEmpty, "不顯示信用額度與剩餘額度")
    }

    @Test("自己的卡(沒有脫敏)詳細頁照舊:五個卡費欄位與額度、剩餘額度")
    func ownDetailRowsUnchanged() {
        let model = detail(SampleAccounts.card)

        #expect(!model.isMasked)
        #expect(model.feeRows.map(\.title) == ["信用卡待繳總額", "已出帳待繳款", "未出帳款", "家庭代墊公帳", "個人私帳消費"])
        #expect(model.limitRows.map(\.title) == ["信用額度", "剩餘額度"])
    }

    // MARK: 非持卡人繳家庭代墊(#140)

    @Test("他人的私卡只有「繳家庭代墊」:沒有繳個人私帳、全額結清、出帳作業、校準、編輯;家庭代墊清償完連繳款都沒有")
    func maskedCardOnlyAllowsPayingSharedDebt() {
        let model = detail(SampleAccounts.meiCardAdvance)

        #expect(model.paymentPresets == [.shared])
        #expect(model.showsActions, "操作區還在，只留繳家庭代墊")
        #expect(!model.canOperate && !model.canEdit && !model.showsRollover)

        let settled = CreditCard(
            id: SampleAccounts.meiCardAdvance.id, name: "小美的信用卡", colorHex: "#F38181", billedDebt: .zero, unbilledDebt: .zero,
            creditLimit: nil, statementDay: 10, paymentDueDay: 25, sharedDebt: .zero, personalDebt: .zero,
            ownerID: UserID("sample-mei"), ownerName: "小美", isMasked: true
        )
        let paidOff = detail(settled)
        #expect(paidOff.paymentPresets.isEmpty)
        #expect(!paidOff.showsActions)
    }

    @Test("自己的私卡與家庭卡:操作區照舊(三個還款入口、出帳作業、校準)")
    func ownCardKeepsEveryAction() {
        let model = detail(SampleAccounts.card)

        #expect(model.paymentPresets == [.shared, .personal, .full])
        #expect(model.showsActions && model.canOperate && model.showsRollover)
    }

    @Test("帳戶頁長按選單:他人私卡只有「繳家庭代墊」，沒有出帳作業;自己的卡照舊")
    func accountsMenuPresets() async {
        let model = await accountsModel(scope: .household)

        #expect(model.paymentPresets(for: SampleAccounts.meiCardAdvance) == [.shared])
        #expect(!model.showsRollover(SampleAccounts.meiCardAdvance))
        #expect(model.paymentPresets(for: SampleAccounts.card) == SampleAccounts.card.paymentPresets)
        #expect(model.showsRollover(SampleAccounts.card))
    }

    private func payment(
        _ card: CreditCard, preset: CardPaymentModel.Preset, isMasked: Bool, repository: InMemoryAccountRepository = .sample()
    ) -> CardPaymentModel {
        let model = CardPaymentModel(
            card: card, preset: preset, bankAccounts: [SampleAccounts.savings], repository: repository, dataVersion: dataVersion,
            isMaskedCard: isMasked, today: { CalendarDay(year: 2026, month: 10, day: 3) }
        )
        model.bankAccountID = SampleAccounts.savings.id
        return model
    }

    @Test("繳他人私卡:不管從哪個入口打開都固定繳家庭代墊、歸屬固定公帳、金額帶入家庭代墊待繳額")
    func paymentIsFixedToSharedDebt() {
        for preset in [CardPaymentModel.Preset.shared, .personal, .full] {
            let model = payment(SampleAccounts.meiCardAdvance, preset: preset, isMasked: true)

            #expect(model.isMaskedCard)
            #expect(model.isShared, "歸屬固定公帳")
            #expect(model.amountText == "1200", "帶入家庭代墊待繳額")
            #expect(model.note == "扣繳【小美的信用卡】卡費 (家庭公帳代墊)")
        }
    }

    @Test("繳他人私卡的金額上限是家庭代墊待繳額，超過時提示專屬訊息;沒超過就送出公帳的還款")
    func paymentCapIsSharedDebt() async {
        let repository = InMemoryAccountRepository.sample()
        let model = payment(SampleAccounts.meiCardAdvance, preset: .shared, isMasked: true, repository: repository)

        model.amountText = "1500"
        #expect(await model.submit() == .invalid)
        #expect(model.errorMessage == "繳款金額不可超過家庭代墊公帳待繳額 $1,200")

        model.amountText = "1200"
        #expect(await model.submit() == .paid)
        let sent = await repository.payments.last
        #expect(sent?.isShared == true && sent?.amount == Money(1200) && sent?.creditCardID == SampleAccounts.meiCardAdvance.id)
    }

    @Test("後端對違規的繳款回 403:訊息原樣顯示，不換成通用錯誤")
    func forbiddenReasonIsShown() async {
        let repository = InMemoryAccountRepository.sample()
        await repository.fail(with: .rejected("權限不足：個人信用卡還款沖銷僅限持卡人本人操作"))
        let model = payment(SampleAccounts.meiCardAdvance, preset: .shared, isMasked: true, repository: repository)

        #expect(await model.submit() == .failed)
        #expect(model.errorMessage == "權限不足：個人信用卡還款沖銷僅限持卡人本人操作")
    }

    @Test("自己的卡的還款照舊:上限是信用卡待繳總額、歸屬看打開的入口")
    func ownCardPaymentUnchanged() async {
        let model = payment(SampleAccounts.card, preset: .personal, isMasked: false)

        #expect(!model.isMaskedCard && !model.isShared)
        model.amountText = "99999"
        #expect(await model.submit() == .invalid)
        #expect(model.errorMessage == "繳款金額不可超過信用卡待繳總額 $15,500")
    }
}

