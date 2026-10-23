import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 家庭頁成員列右側 ⋯ 選單(#274):明細、沖銷、標記處理,最後是破壞性的移除。
/// 沒有權限或用不到的項目直接不給(HIG Context menus:隱藏、不要變灰)。
@MainActor
@Suite("家庭頁成員 ⋯ 選單")
struct MemberMenuTests {
    private let me = InMemoryAuthRepository.Member.sample.user.id
    private let mei = UserID("sample-mei")
    private let today = CalendarDay(year: 2026, month: 9, day: 28)

    private func advance(for id: UserID, pending: Int, items: Bool = true) -> HouseholdAdvance {
        let item = AdvanceItem(
            id: TransactionID("t-\(id.rawValue)"), date: today, category: .dining, note: "午餐", amount: Money(Decimal(max(pending, 1))),
            accountName: "iOS 測試皮夾", accountKind: .cash
        )
        return HouseholdAdvance(
            memberID: id, memberName: id == me ? "小明" : "小美", totalAdvanced: Money(Decimal(pending)), totalReimbursed: .zero,
            pendingReimbursement: Money(Decimal(pending)), advanceItems: items ? [item] : [], reimbursementItems: []
        )
    }

    private func loaded(role: HouseholdRole, advances: [HouseholdAdvance]) async -> HouseholdModel {
        let model = HouseholdModel(
            repository: InMemoryHouseholdRepository.sample(myRole: role, advances: advances),
            accounts: InMemoryAccountRepository.sample(), currentUser: me, dataVersion: DataVersion(), today: { today }
        )
        await model.load()
        return model
    }

    private func items(_ model: HouseholdModel, memberID: UserID) -> [MemberMenuItem] {
        let member = model.household?.members.first { $0.userID == memberID }
        return model.memberMenuItems(for: member, advance: model.advance(of: memberID))
    }

    @Test("家庭管理員看一般成員:明細、沖銷、標記處理、移除,順序固定,移除在最後")
    func adminOnMember() async {
        let model = await loaded(role: .admin, advances: [advance(for: mei, pending: 500)])
        #expect(items(model, memberID: mei) == [.details, .reimburse, .markSettled, .remove])
    }

    @Test("家庭管理員看自己:沒有移除(移除只對一般成員)")
    func adminOnSelf() async {
        let model = await loaded(role: .admin, advances: [advance(for: me, pending: 500)])
        #expect(items(model, memberID: me) == [.details, .reimburse, .markSettled])
    }

    @Test("一般成員:自己的列有沖銷與標記處理,別人的列只有明細")
    func memberOnlyOwn() async {
        let model = await loaded(role: .member, advances: [advance(for: me, pending: 500), advance(for: mei, pending: 500)])
        #expect(items(model, memberID: me) == [.details, .reimburse, .markSettled])
        #expect(items(model, memberID: mei) == [.details])
    }

    @Test("已全數結清:只有明細;公帳待抵扣:不能沖銷,但仍可標記處理")
    func settledAndOffset() async {
        let settled = advance(for: mei, pending: 0, items: false)
        let model = await loaded(role: .admin, advances: [settled])
        #expect(items(model, memberID: mei) == [.details, .remove])

        let offset = advance(for: mei, pending: -200)
        let model2 = await loaded(role: .admin, advances: [offset])
        #expect(items(model2, memberID: mei) == [.details, .markSettled, .remove])
    }

    @Test("沒有代墊統計的成員:沒有明細、沖銷與標記處理,管理員仍可移除一般成員")
    func noAdvance() async {
        let model = await loaded(role: .admin, advances: [])
        #expect(items(model, memberID: mei) == [.remove])
    }
}
