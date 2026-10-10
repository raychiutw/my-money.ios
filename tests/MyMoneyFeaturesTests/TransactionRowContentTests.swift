import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 一列收支明細要呈現的全部內容(#208 第 5 項):標題、次要文字、帳戶、金額呈現、圖示與 VoiceOver 整句,
/// 由同一個 module 一次決定;列元件只負責排版。
@MainActor
@Suite("收支明細列的內容(TransactionRowContent)")
struct TransactionRowContentTests {
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let me = InMemoryAuthRepository.Member.sample.user

    private func tx(
        note: String = "午餐", type: TransactionType = .expense, category: TransactionCategory = .dining, amount: Int = 120,
        shared: Bool = true, accountName: String? = SampleAccounts.savings.name, recorder: String? = nil, recorderID: UserID? = nil,
        billing: BillingStatus = .unbilled, recordedAt: Date? = nil, payment: HouseholdPayment? = nil
    ) -> MyMoneyDomain.Transaction {
        MyMoneyDomain.Transaction(
            id: TransactionID("row"), accountID: SampleAccounts.savings.id, accountName: accountName, type: type, category: category,
            amount: Money(Decimal(amount)), note: note, date: today, isShared: shared, recorderName: recorder, recorderID: recorderID,
            billing: billing, recordedAt: recordedAt, householdPayment: payment
        )
    }

    @Test("標題是備註,沒有備註時用分類名稱")
    func title() {
        #expect(TransactionRowContent(tx(note: "午餐"), viewer: nil).title == "午餐")
        #expect(TransactionRowContent(tx(note: ""), viewer: nil).title == "餐飲")
    }

    @Test("金額呈現:支出紅色負數、收入綠色正數")
    func amount() {
        #expect(TransactionRowContent(tx(type: .expense, amount: 120), viewer: nil).amount == .outflow(Money(120)))
        #expect(TransactionRowContent(tx(type: .income, category: .salary, amount: 45000), viewer: nil).amount == .inflow(Money(45000)))
    }

    @Test("圖示取自分類")
    func symbol() {
        #expect(TransactionRowContent(tx(), viewer: nil).symbolName == TransactionCategory.dining.symbolName)
    }

    @Test("帳戶名稱:有就顯示在右邊;沒有時不顯示,念法用「預設帳戶」")
    func account() {
        #expect(TransactionRowContent(tx(accountName: "iOS 測試存款"), viewer: nil).accountName == "iOS 測試存款")
        let none = TransactionRowContent(tx(accountName: nil), viewer: nil)
        #expect(none.accountName == nil)
        #expect(none.spokenText.contains("帳戶 預設帳戶"))
    }

    @Test("VoiceOver 整句:分類、備註、帳戶、(時間)、(記帳人)、歸屬、(帳單狀態)、收支方向與金額")
    func spoken() throws {
        let time = try #require(RecordedTime.date(fromBackend: "2026-09-27 19:57:02"))
        let content = TransactionRowContent(
            tx(shared: true, recorder: "小美", recorderID: UserID("mei"), billing: .deferred, recordedAt: time), viewer: me.id
        )
        let parts = content.spokenText.split(separator: "，").map(String.init)

        #expect(parts.first == "餐飲")
        #expect(parts.contains("午餐"))
        #expect(parts.contains("帳戶 iOS 測試存款"))
        #expect(parts.contains("記帳人 小美"))
        #expect(parts.contains("家庭公帳"))
        #expect(parts.contains(Terms.deferredToNextStatement))
        #expect(parts.last == "支出 120 元")
        // 順序:帳戶 → 時間 → 記帳人 → 歸屬。
        let account = try #require(parts.firstIndex(of: "帳戶 iOS 測試存款"))
        let recorder = try #require(parts.firstIndex(of: "記帳人 小美"))
        #expect(account + 2 == recorder, "帳戶與記帳人之間是時間")
    }

    @Test("自己記的不念記帳人;沒有備註不重複念分類;沒有時間不念")
    func spokenOmissions() {
        let mine = TransactionRowContent(tx(note: "", recorder: me.name, recorderID: me.id), viewer: me.id)
        #expect(mine.spokenText == "餐飲，帳戶 iOS 測試存款，家庭公帳，支出 120 元")
        #expect(mine.spokenRecorder == nil)
    }

    @Test("記帳人只有不是自己記的才念;用 ID 判斷,家人可能同名")
    func spokenRecorder() {
        #expect(TransactionRowContent(tx(recorder: me.name, recorderID: me.id), viewer: me.id).spokenRecorder == nil)
        #expect(TransactionRowContent(tx(recorder: "小美", recorderID: UserID("mei")), viewer: me.id).spokenRecorder == "小美")
        #expect(TransactionRowContent(tx(recorder: me.name, recorderID: UserID("another")), viewer: me.id).spokenRecorder == me.name)
        #expect(TransactionRowContent(tx(recorder: "小美", recorderID: UserID("mei")), viewer: nil).spokenRecorder == "小美")
    }

    @Test("公帳三態(上游 d0424df):次要文字的歸屬那一段與 VoiceOver 都念出狀態")
    func householdPaymentStates() {
        let direct = TransactionRowContent(tx(payment: .jointFund), viewer: nil)
        #expect(direct.subtitle.ownership == "家庭公帳")
        #expect(direct.spokenText.contains("，家庭公帳，"))

        let pending = TransactionRowContent(tx(payment: .advancePending), viewer: nil)
        #expect(pending.subtitle.ownership == "家庭公帳・待報銷")
        #expect(pending.spokenText.contains("，家庭公帳・待報銷，"))

        let reimbursed = TransactionRowContent(tx(payment: .advanceReimbursed), viewer: nil)
        #expect(reimbursed.subtitle.ownership == "家庭公帳・已撥款")
        #expect(reimbursed.spokenText.contains("，家庭公帳・已撥款，"))
    }

    @Test("私帳不受影響;公帳狀態未知時維持「家庭公帳」;與帳單狀態接在後面")
    func privateAndUnknownAndBilling() {
        #expect(TransactionRowContent(tx(shared: false, payment: nil), viewer: nil).subtitle.ownership == "個人私帳")
        #expect(TransactionRowContent(tx(shared: true, payment: nil), viewer: nil).subtitle.ownership == "家庭公帳")
        let card = TransactionRowContent(tx(billing: .deferred, payment: .advancePending), viewer: nil)
        #expect(card.subtitle.tail == "家庭公帳・待報銷・延至下期")
    }
}
