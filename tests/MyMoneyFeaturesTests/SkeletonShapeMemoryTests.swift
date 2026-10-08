import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 帳戶頁、家庭頁的骨架屏跟著實際內容(#204):記住上次載入完成時各區塊幾張卡、有沒有家庭。只記數量與狀態,不記內容。
@MainActor
@Suite("骨架屏的形狀記憶(帳戶與家庭)")
struct SkeletonShapeMemoryTests {
    private func defaults() -> UserDefaults {
        let suite = "SkeletonShapeMemoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("數量:沒有記錄用預設;有記錄用記錄;超過上限只畫上限")
    func counts() {
        let memory = SkeletonShapeMemory(defaults: defaults())
        #expect(memory.count(for: "bank", default: 1) == 1)

        memory.record(count: 3, for: "bank")
        memory.record(count: 0, for: "cash")
        memory.record(count: 9, for: "card")

        #expect(memory.count(for: "bank", default: 1) == 3)
        #expect(memory.count(for: "cash", default: 1) == 0, "上次沒有現金帳戶:骨架不畫那一區")
        #expect(memory.count(for: "card", default: 1, limit: 4) == 4)
    }

    @Test("旗標:沒有記錄是 nil,有記錄照記錄")
    func flags() {
        let memory = SkeletonShapeMemory(defaults: defaults())
        #expect(memory.flag(for: "joined") == nil)

        memory.record(flag: true, for: "joined")

        #expect(memory.flag(for: "joined") == true)
    }

    @Test("帳戶頁載入完成後記下各區塊的張數;下一次的骨架照它畫")
    func accountsRemembersTheCounts() async {
        let defaults = defaults()
        let first = AccountsModel(repository: InMemoryAccountRepository.sample(), dataVersion: DataVersion(), defaults: defaults)
        #expect(first.skeletonCounts == .init(cash: 0, bank: 1, creditCard: 1), "第一次沒有記錄:預設現金 0、活存帳戶 1、信用卡 1")

        await first.load()

        let second = AccountsModel(repository: InMemoryAccountRepository.sample(), dataVersion: DataVersion(), defaults: defaults)
        #expect(second.skeletonCounts == .init(cash: 0, bank: 1, creditCard: 2), "範例資料:1 個活存帳戶、2 張信用卡")
    }

    @Test("家庭頁:沒有記錄時骨架畫成還沒加入;載入後記下有沒有家庭與成員數")
    func householdRemembersJoinedState() async {
        let defaults = defaults()
        let repository = InMemoryHouseholdRepository.sample(advances: [])
        let first = HouseholdModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(), dataVersion: DataVersion(), defaults: defaults
        )
        #expect(first.skeletonShape == HouseholdModel.SkeletonShape.notJoined)

        await first.load()

        let second = HouseholdModel(
            repository: repository, accounts: InMemoryAccountRepository.sample(), dataVersion: DataVersion(), defaults: defaults
        )
        #expect(second.skeletonShape == HouseholdModel.SkeletonShape.joined(members: 2, hasMyAdvance: false))
    }
}
