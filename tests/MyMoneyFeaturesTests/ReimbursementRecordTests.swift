import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 撥款沖帳紀錄的編輯與刪除(上游 ADR 0031,#314)。
@MainActor
@Suite("撥款沖帳紀錄:編輯與刪除")
struct ReimbursementRecordTests {
    private let dataVersion = DataVersion()
    private let me = InMemoryAuthRepository.Member.sample.user.id
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let mine = InMemoryHouseholdRepository.myAdvanceWithStates
    private let mei = InMemoryHouseholdRepository.meiOffsetAdvance

    private func loaded(role: HouseholdRole) async -> (HouseholdModel, InMemoryHouseholdRepository) {
        let repository = InMemoryHouseholdRepository.sample(myRole: role, advances: [mine, mei])
        let model = HouseholdModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(), currentUser: me, dataVersion: dataVersion,
            locale: Locale(identifier: "zh_Hant_TW"), today: { today }
        )
        await model.load()
        return (model, repository)
    }

    private var item: ReimbursementItem { mine.reimbursementItems[0] }

    @Test("權限:家庭管理員改得了任何成員的紀錄;一般成員只有自己的")
    func permissions() async {
        let (admin, _) = await loaded(role: .admin)
        #expect(admin.canModifyReimbursement(in: mine) && admin.canModifyReimbursement(in: mei))
        let (member, _) = await loaded(role: .member)
        #expect(member.canModifyReimbursement(in: mine))
        #expect(!member.canModifyReimbursement(in: mei))
    }

    @Test("編輯:帶入原值;送出金額、日期、備註,資料版本遞增並重新載入")
    func edit() async throws {
        let (model, repository) = await loaded(role: .admin)
        let editor = try #require(model.makeReimbursementEditor(for: item, in: mine))
        #expect(editor.amountText == "600")
        #expect(editor.note == "撥款報銷家庭晚餐")
        #expect(editor.date == item.date)
        editor.amountText = "700"
        editor.note = "改過"
        editor.date = item.date.addingDays(1)

        #expect(await editor.save())

        let update = try #require(await repository.updatedReimbursements.first)
        #expect(update.id == item.id)
        #expect(update.amount == Money(700))
        #expect(update.note == "改過")
        #expect(update.date == item.date.addingDays(1))
        #expect(dataVersion.value == 1)
        #expect(model.advance(of: me)?.reimbursementItems.first?.amount == Money(700))
    }

    @Test("編輯:金額不是正整數就不送出")
    func invalidAmount() async throws {
        let (model, repository) = await loaded(role: .admin)
        let editor = try #require(model.makeReimbursementEditor(for: item, in: mine))
        editor.amountText = "0"

        #expect(!(await editor.save()))
        #expect(editor.errorMessage == "請輸入有效的報銷金額")
        #expect(await repository.updatedReimbursements.isEmpty)
    }

    @Test("編輯失敗(例如報銷改得比已結清代墊少):錯誤顯示在表單裡,資料版本不變")
    func editFailure() async throws {
        let (model, repository) = await loaded(role: .admin)
        let editor = try #require(model.makeReimbursementEditor(for: item, in: mine))
        await repository.fail(with: .rejected("修改後報銷金額不得低於目前已結清代墊明細合計。請先至「已結清明細」解除部分項目報銷。"))
        editor.amountText = "100"

        #expect(!(await editor.save()))
        #expect(editor.errorMessage?.contains("已結清明細") == true)
        #expect(dataVersion.value == 0)
    }

    @Test("沒有權限的人打不開編輯器、刪不掉")
    func guards() async throws {
        let (member, repository) = await loaded(role: .member)
        let meiItem = ReimbursementItem(id: TransactionID("mei-r"), date: today, amount: Money(1), note: "x", accountName: "y")
        #expect(member.makeReimbursementEditor(for: meiItem, in: mei) == nil)
        await member.deleteReimbursement(meiItem, in: mei)
        #expect(await repository.deletedReimbursementIDs.isEmpty)
    }

    @Test("刪除:送出那一筆,資料版本遞增,紀錄消失")
    func delete() async throws {
        let (model, repository) = await loaded(role: .admin)

        await model.deleteReimbursement(item, in: mine)

        #expect(await repository.deletedReimbursementIDs == [item.id])
        #expect(dataVersion.value == 1)
        #expect(model.advance(of: me)?.reimbursementItems.isEmpty == true)
    }

    @Test("刪除失敗:顯示後端的錯誤,資料版本不變")
    func deleteFailure() async throws {
        let (model, repository) = await loaded(role: .admin)
        await repository.fail(with: .rejected("權限不足"))

        await model.deleteReimbursement(item, in: mine)

        #expect(model.alertMessage == "權限不足")
        #expect(dataVersion.value == 0)
    }
}
