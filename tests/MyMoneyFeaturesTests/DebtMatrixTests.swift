import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 信用卡欠款的雙層公私矩陣(上游 ADR 0025):詳細頁的拆解、繳家庭代墊的預設金額與快速切換、他人私卡的脫敏版型。
@MainActor
@Suite("信用卡欠款矩陣(上游 ADR 0025)")
struct DebtMatrixTests {
    private let dataVersion = DataVersion()

    /// 數字取自 prod 錄下的真實回應(卡 25 出帳之後):已出帳 公帳 900、私帳 300;未出帳 公帳 0、私帳 150。
    private func card(
        billedShared: Int = 900, billedPersonal: Int = 300, unbilledShared: Int = 0, unbilledPersonal: Int = 150,
        masked: Bool = false, withMatrix: Bool = true
    ) -> CreditCard {
        let bs = Money(Decimal(billedShared)), bp = Money(Decimal(billedPersonal))
        let us = Money(Decimal(unbilledShared)), up = Money(Decimal(unbilledPersonal))
        return CreditCard(
            id: AccountID("card"), name: "iOS 暫存卡25", colorHex: "#FFD4A0", billedDebt: bs + bp, unbilledDebt: us + up,
            creditLimit: masked ? nil : Money(50000), statementDay: 25, paymentDueDay: 10, sharedDebt: bs + us, personalDebt: bp + up,
            ownerID: masked ? UserID("sample-mei") : InMemoryAuthRepository.Member.sample.user.id,
            isMasked: masked,
            debtMatrix: withMatrix ? DebtMatrix(billedShared: bs, billedPersonal: bp, unbilledShared: us, unbilledPersonal: up) : nil
        )
    }

    private func detail(_ card: CreditCard) -> CreditCardDetailModel {
        CreditCardDetailModel(
            card: card, bankAccounts: [SampleAccounts.savings], loadedVersion: dataVersion.value, scope: .all,
            repository: InMemoryAccountRepository.sample(), dataVersion: dataVersion, today: { CalendarDay(year: 2026, month: 10, day: 17) }
        )
    }

    // MARK: 詳細頁的拆解

    @Test("詳細頁:已出帳與未出帳各自列出公帳與私帳,總公帳、總私帳仍在")
    func feeRowsShowTheMatrix() {
        let rows = detail(card()).feeRows

        #expect(rows.map(\.title) == [
            "信用卡待繳總額", "已出帳待繳款", "已出帳公帳", "已出帳私帳", "未出帳款", "未出帳公帳", "未出帳私帳", "家庭代墊公帳", "個人私帳消費",
        ])
        #expect(rows.map(\.value) == ["$1,350", "$1,200", "$900", "$300", "$150", "$0", "$150", "$900", "$450"])
    }

    @Test("舊的回應沒有矩陣:詳細頁維持原本的五列")
    func feeRowsWithoutMatrix() {
        #expect(detail(card(withMatrix: false)).feeRows.map(\.title) == [
            "信用卡待繳總額", "已出帳待繳款", "未出帳款", "家庭代墊公帳", "個人私帳消費",
        ])
    }

    @Test("他人私卡(脫敏):只多揭露已出帳公帳與未出帳公帳，個人的部分維持隱私遮蔽")
    func maskedCardRevealsOnlyTheSharedParts() {
        let rows = detail(card(billedPersonal: 0, unbilledShared: 250, unbilledPersonal: 0, masked: true)).feeRows

        #expect(rows.map(\.title) == [
            "家庭公帳代墊待繳總額", "本期已出帳公帳待繳", "未出帳公帳累計", "個人帳單狀態", "公帳代墊待清償", "個人私帳消費",
        ])
        #expect(rows.map(\.value) == ["$1,150", "$900", "$250", "隱私遮蔽", "$1,150", "隱私遮蔽"])
    }

    // MARK: 繳家庭代墊的預設金額與快速切換

    @Test("繳家庭代墊:已出帳公帳大於 0 就預設填已出帳公帳(不是含未出帳的全部公帳)")
    func sharedPaymentDefaultsToBilledShared() {
        let payment = detail(card(unbilledShared: 250)).makePayment(.shared)

        #expect(payment.amountText == "900")
        #expect(payment.isShared)
    }

    @Test("已出帳公帳是 0 時預設填未出帳公帳")
    func sharedPaymentFallsBackToUnbilledShared() {
        let payment = detail(card(billedShared: 0, unbilledShared: 250)).makePayment(.shared)

        #expect(payment.amountText == "250")
        #expect(payment.sharedChoices.isEmpty, "沒有已出帳公帳，沒有可切換的選項")
    }

    @Test("快速切換:僅繳當期已出帳公帳 / 結清全部代墊公帳,選了金額欄跟著變，可以切回來")
    func quickSwitchBetweenBilledAndAllShared() {
        let payment = detail(card(unbilledShared: 250)).makePayment(.shared)

        #expect(payment.sharedChoices == [.billedOnly, .all])
        #expect(payment.sharedChoice == .billedOnly)
        #expect(payment.sharedChoiceTitle(.billedOnly) == "僅繳當期已出帳公帳 $900")
        #expect(payment.sharedChoiceTitle(.all) == "結清全部代墊公帳 $1,150")

        payment.sharedChoice = .all
        #expect(payment.amountText == "1150")
        payment.sharedChoice = .billedOnly
        #expect(payment.amountText == "900")
    }

    @Test("兩個選項金額一樣(未出帳公帳是 0)時不出現快速切換，免得兩個一樣的選項")
    func noQuickSwitchWhenAmountsAreTheSame() {
        #expect(detail(card()).makePayment(.shared).sharedChoices.isEmpty)
    }

    @Test("繳個人私帳、全額結清不受影響;沒有矩陣的舊回應繳家庭代墊填總公帳、沒有快速切換")
    func otherPresetsAndOldResponses() {
        let current = card(unbilledShared: 250)
        #expect(detail(current).makePayment(.personal).amountText == "450")
        #expect(detail(current).makePayment(.full).amountText == "1600")

        let old = detail(card(withMatrix: false)).makePayment(.shared)
        #expect(old.amountText == "900")
        #expect(old.sharedChoices.isEmpty)
    }

    @Test("他人私卡:繳家庭代墊同樣先填已出帳公帳，也有快速切換;金額上限是全部公帳")
    func maskedCardPayment() async {
        let masked = card(billedPersonal: 0, unbilledShared: 250, unbilledPersonal: 0, masked: true)
        let payment = detail(masked).makePayment(.shared)

        #expect(payment.amountText == "900")
        #expect(payment.sharedChoices == [.billedOnly, .all])
        payment.sharedChoice = .all
        #expect(payment.amountText == "1150")
    }
}
