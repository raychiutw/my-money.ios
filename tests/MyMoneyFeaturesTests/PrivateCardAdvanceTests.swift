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

    @Test("卡片小字:公帳範圍的個人卡寫「私卡代墊」加繳款日;其他範圍照舊寫公帳或私帳")
    func captions() async {
        let household = await accountsModel(scope: .household)
        #expect(household.caption(for: SampleAccounts.meiCardAdvance) == "私卡代墊・25 日繳")
        #expect(household.caption(for: SampleAccounts.card) == "私卡代墊・5 日繳", "自己的私卡在公帳範圍也標私卡代墊")

        let all = await accountsModel(scope: .all)
        #expect(all.caption(for: SampleAccounts.card) == "私帳・5 日繳")
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
        #expect(all.spokenSummary(of: SampleAccounts.card) == "iOS 測試信用卡，私帳，信用卡待繳總額 15,500 元，每月 5 日繳款")
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
}
