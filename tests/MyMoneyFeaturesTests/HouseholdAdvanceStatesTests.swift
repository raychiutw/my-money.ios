import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 家庭代墊的新狀態(上游 ADR 0027、0029、`fe90634`):公帳退款負項、公帳待抵扣、已結清明細、解除報銷、標記已額外處理、信用卡出帳標示。
@MainActor
@Suite("家庭代墊的狀態")
struct HouseholdAdvanceStatesTests {
    private let dataVersion = DataVersion()
    private let me = InMemoryAuthRepository.Member.sample.user.id
    private let today = CalendarDay(year: 2026, month: 9, day: 28)
    private let mine = InMemoryHouseholdRepository.myAdvanceWithStates
    private let mei = InMemoryHouseholdRepository.meiOffsetAdvance

    private func loaded(
        role: HouseholdRole = .admin, repository: InMemoryHouseholdRepository? = nil
    ) async -> (HouseholdModel, InMemoryHouseholdRepository) {
        let repository = repository ?? .sample(myRole: role, advances: [mine, mei])
        let model = HouseholdModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(), currentUser: me, dataVersion: dataVersion,
            locale: Locale(identifier: "zh_Hant_TW"), today: { today }
        )
        await model.load()
        return (model, repository)
    }

    // MARK: 公帳待抵扣

    @Test("待報銷是負的(公帳退款比待報銷的支出多):公帳待抵扣，不能撥款報銷")
    func offsetPending() async {
        let (model, _) = await loaded()

        #expect(mei.isOffsetPending)
        #expect(model.pendingStatusText(of: mei) == "公帳待抵扣")
        #expect(!model.canReimburse(mei), "待報銷不大於 0 就停用撥款報銷")
        #expect(model.pendingStatusText(of: mine) == nil)
        #expect(model.canReimburse(mine))
    }

    // MARK: 明細的標示

    @Test("信用卡扣款的明細標示出帳狀態:未出帳、已出帳、延至下期;現金墊付沒有")
    func billingText() async {
        let (model, _) = await loaded()
        let items = Dictionary(uniqueKeysWithValues: mine.advanceItems.map { ($0.id.rawValue, $0) })

        #expect(model.billingText(of: items["sample-refund"]!) == "未出帳")
        #expect(model.billingText(of: items["sample-card-billed"]!) == "已出帳")
        #expect(model.billingText(of: items["sample-card-deferred"]!) == "延至下期")
        #expect(model.billingText(of: items["sample-advance"]!) == nil)
    }

    @Test("已結清明細說明怎麼結清的:撥款結清寫日期與金額，已額外處理另寫")
    func settlementText() async throws {
        let (model, _) = await loaded()
        let reimbursed = try #require(mine.settledItems.first { $0.id.rawValue == "sample-settled-reimbursed" })
        let external = try #require(mine.settledItems.first { $0.id.rawValue == "sample-settled-external" })

        #expect(model.settlementText(of: reimbursed, in: mine) == "9月25日撥款 $600 結清")
        #expect(model.settlementText(of: external, in: mine) == "已額外處理")
    }

    // MARK: 權限

    @Test("解除報銷:家庭管理員任何一筆都可以;一般成員只有自己的")
    func unlinkPermissions() async throws {
        let (admin, _) = await loaded(role: .admin)
        let settled = try #require(mine.settledItems.first)
        #expect(admin.canUnlink(settled, in: mine))
        #expect(admin.canUnlink(settled, in: mei))

        let (member, _) = await loaded(role: .member)
        #expect(member.canUnlink(settled, in: mine), "自己的代墊")
        #expect(!member.canUnlink(settled, in: mei), "別人的代墊(後端回 403)")
    }

    @Test("標記已額外處理:有待報銷明細才有;家庭管理員任何成員、一般成員只有自己")
    func markSettledPermissions() async {
        let (admin, _) = await loaded(role: .admin)
        #expect(admin.canMarkSettled(mine))
        #expect(admin.canMarkSettled(mei))

        let (member, _) = await loaded(role: .member)
        #expect(member.canMarkSettled(mine))
        #expect(!member.canMarkSettled(mei))

        let none = HouseholdAdvance(
            memberID: me, memberName: "小明", totalAdvanced: .zero, totalReimbursed: .zero, pendingReimbursement: .zero,
            advanceItems: [], reimbursementItems: []
        )
        #expect(!admin.canMarkSettled(none), "沒有待報銷明細沒有東西可標記")
    }

    // MARK: 操作

    @Test("解除報銷:送出那一筆,顯示後端的訊息，資料版本遞增，明細回到待報銷")
    func unlink() async throws {
        let (model, repository) = await loaded()
        let settled = try #require(mine.settledItems.first { $0.id.rawValue == "sample-settled-reimbursed" })

        await model.unlink(settled)

        #expect(await repository.unlinkedIDs == [settled.id])
        #expect(model.noticeMessage == "已成功解除報銷，該筆明細已退回待報銷清單")
        #expect(dataVersion.value == 1)
        let advance = try #require(model.advance(of: me))
        #expect(advance.advanceItems.map(\.id.rawValue).contains("sample-settled-reimbursed"))
        #expect(advance.settledItems.count == 1)
        #expect(advance.pendingReimbursement == Money(1450), "850 + 600")
        #expect(advance.linkedReimbursed == .zero)
    }

    @Test("解除報銷失敗:顯示後端的錯誤，資料版本不變")
    func unlinkFailure() async throws {
        let (model, repository) = await loaded()
        await repository.fail(with: .rejected("權限不足：僅該筆收支記錄者或家庭管理員可解除報銷"))

        await model.unlink(try #require(mine.settledItems.first))

        #expect(model.alertMessage == "權限不足：僅該筆收支記錄者或家庭管理員可解除報銷")
        #expect(model.noticeMessage == nil)
        #expect(dataVersion.value == 0)
    }

    @Test("標記已額外處理:送出勾選的明細，移到已結清(已額外處理),待報銷減少，共同基金的累計撥款不變")
    func markSettled() async throws {
        let (model, repository) = await loaded()

        await model.markSettled([TransactionID("sample-card-billed")], for: mine)

        #expect(await repository.markedSettled.map(\.ids) == [[TransactionID("sample-card-billed")]])
        #expect(model.noticeMessage == "已將 1 筆公帳代墊項目移出待報銷清單（標記為已額外處理完成）！")
        #expect(dataVersion.value == 1)
        let advance = try #require(model.advance(of: me))
        #expect(advance.advanceItems.map(\.id.rawValue) == ["sample-advance", "sample-refund", "sample-card-deferred"])
        #expect(advance.settledItems.first?.settlement == .handledSeparately)
        #expect(advance.pendingReimbursement == Money(450), "850 − 400")
        #expect(advance.totalReimbursed == Money(800), "不動共同基金、不虛增撥款")
        #expect(advance.linkedReimbursed == Money(600))
    }

    @Test("沒勾選就標記:後端拒絕，顯示原文")
    func markSettledWithoutSelection() async {
        let (model, _) = await loaded()

        await model.markSettled([], for: mine)

        #expect(model.alertMessage == "請至少勾選一筆要標記已額外處理的代墊明細")
        #expect(dataVersion.value == 0)
    }

    // MARK: 報銷沖帳:退款負項

    @Test("報銷沖帳的逐筆勾選:報銷金額是勾選明細的淨額(支出減退款);只選退款不能送出")
    func reimbursementNetAmount() async throws {
        let (model, _) = await loaded()
        let reimbursement = model.makeReimbursement(for: mine)
        await reimbursement.load()

        // 預設全選:250 − 100 + 400 + 300 = 850。
        #expect(reimbursement.selectedAmount == Money(850))

        reimbursement.toggle(TransactionID("sample-advance"))
        reimbursement.toggle(TransactionID("sample-card-billed"))
        reimbursement.toggle(TransactionID("sample-card-deferred"))
        #expect(reimbursement.selectedAmount == Money(-100), "只剩退款")
        #expect(!reimbursement.canSubmit, "淨額不大於 0 不能撥款")
    }
}
