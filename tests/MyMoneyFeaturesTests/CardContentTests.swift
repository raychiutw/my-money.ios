import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 明細卡第三版的內容(#287):標題用分類中文、膠囊清單(歸屬、銷帳或出帳狀態、帳戶)、建檔人頭像字、備註、不含時間。
@MainActor
@Suite("明細卡內容")
struct CardContentTests {
    private let me = UserID("card-me")
    private let today = CalendarDay(year: 2026, month: 10, day: 24)

    private func content(
        category: TransactionCategory = .dining, note: String = "晚餐", shared: Bool = true, payment: HouseholdPayment? = nil,
        billing: BillingStatus = .unbilled, recorder: String? = "Ray", account: String? = "玉山 U Bear", recordedAt: Date? = nil
    ) -> TransactionRowContent {
        TransactionRowContent(
            Transaction(
                id: TransactionID("c"), accountID: AccountID("a"), accountName: account, type: .expense, category: category,
                amount: Money(201), note: note, date: today, isShared: shared, recorderName: recorder, recorderID: me,
                billing: billing, recordedAt: recordedAt, householdPayment: payment
            ),
            viewer: me
        )
    }

    @Test("標題是分類中文,不是備註;備註獨立放第三排")
    func titleIsTheCategory() {
        let card = content(category: .dining, note: "晚餐-subway")
        #expect(card.categoryTitle == "餐飲")
        #expect(card.note == "晚餐-subway")
        #expect(content(note: "").note == nil, "沒有備註就沒有第三排")
    }

    @Test("系統分類的標題是系統分類名稱")
    func systemCategoryTitle() {
        #expect(content(category: .creditCardRepayment, recorder: nil).categoryTitle == "信用卡還款")
    }

    @Test("膠囊清單:歸屬、銷帳狀態、帳戶,順序固定")
    func chipsInOrder() {
        #expect(content(shared: true, payment: .advancePending).chips == ["家庭公帳", "待報銷", "玉山 U Bear"])
        #expect(content(shared: true, payment: .advanceReimbursed).chips == ["家庭公帳", "已撥款", "玉山 U Bear"])
        #expect(content(shared: true, payment: .advanceHandledSeparately).chips == ["家庭公帳", "已額外處理", "玉山 U Bear"])
    }

    @Test("沒有銷帳狀態的不放那顆(共同帳戶直接扣款、個人私帳)")
    func chipsWithoutStatus() {
        #expect(content(shared: true, payment: .jointFund).chips == ["家庭公帳", "玉山 U Bear"])
        #expect(content(shared: false).chips == ["個人私帳", "玉山 U Bear"])
    }

    @Test("信用卡的出帳狀態在銷帳狀態的位置:已出帳、延至下期;未出帳不標")
    func billingStatusChip() {
        #expect(content(shared: false, billing: .billed).chips == ["個人私帳", "已出帳", "玉山 U Bear"])
        #expect(content(shared: false, billing: .deferred).chips == ["個人私帳", "延至下期", "玉山 U Bear"])
        #expect(content(shared: false, billing: .unbilled).chips == ["個人私帳", "玉山 U Bear"])
    }

    @Test("沒有帳戶名稱就沒有帳戶那顆")
    func noAccountChip() {
        #expect(content(shared: false, account: nil).chips == ["個人私帳"])
    }

    @Test("建檔人頭像字:名字第一個字;系統紀錄是「系」;沒有建檔人沒有頭像")
    func avatarInitial() {
        #expect(content(recorder: "Ray").avatarInitial == "R")
        #expect(content(recorder: "小明").avatarInitial == "小")
        #expect(content(category: .creditCardRepayment, recorder: nil).avatarInitial == "系")
        #expect(content(recorder: nil).avatarInitial == nil)
        #expect(content(category: .creditCardRepayment, recorder: nil).isSystemRecord)
        #expect(!content(recorder: "Ray").isSystemRecord)
    }

    @Test("卡片上沒有時間;VoiceOver 整句仍然念出時間")
    func noTimeOnCardButSpoken() throws {
        let date = try #require(RecordedTime.date(fromBackend: "2026-09-27 19:57:02"))
        let card = content(recordedAt: date)
        #expect(!card.chips.contains { $0.contains(":") })
        #expect(card.spokenText.contains("03:57") || card.spokenText.contains("3:57") || card.spokenText.contains("凌晨"))
    }

    @Test("VoiceOver 整句含分類、備註、帳戶、歸屬與狀態、收支方向、金額")
    func spokenSentence() {
        let spoken = content(shared: true, payment: .advancePending).spokenText
        for part in ["餐飲", "晚餐", "玉山 U Bear", "家庭公帳", "待報銷", "支出"] {
            #expect(spoken.contains(part), "整句少了「\(part)」:\(spoken)")
        }
    }
}
