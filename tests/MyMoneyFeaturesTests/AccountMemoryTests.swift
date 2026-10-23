import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

/// 記住的帳戶(#273):每個選帳戶的功能各自記住上次選的帳戶;偏離上游 ADR 0011 的「不預選」,
/// 預選的是使用者自己上次的選擇,仍可改選。
@MainActor
@Suite("帳戶記憶(AccountMemory)")
struct AccountMemoryTests {
    private let suite = "AccountMemoryTests-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    private let me = UserID("memory-me")
    private let savings = SampleAccounts.savings.id
    private let accounts: [Account] = SampleAccounts.all

    @Test("沒記過:沒有帶入")
    func empty() {
        defaults.removePersistentDomain(forName: suite)
        let memory = AccountMemory(defaults: defaults, userID: me, purpose: .quickEntry)
        #expect(memory.recall(among: accounts) == nil)
    }

    @Test("記過之後讀回同一個帳戶")
    func roundTrip() {
        defaults.removePersistentDomain(forName: suite)
        AccountMemory(defaults: defaults, userID: me, purpose: .quickEntry).remember(savings)
        #expect(AccountMemory(defaults: defaults, userID: me, purpose: .quickEntry).recall(among: accounts) == savings)
    }

    @Test("每個選帳戶的功能各自記憶,互不影響")
    func purposesAreIndependent() {
        defaults.removePersistentDomain(forName: suite)
        AccountMemory(defaults: defaults, userID: me, purpose: .quickEntry).remember(savings)
        #expect(AccountMemory(defaults: defaults, userID: me, purpose: .transferFrom).recall(among: accounts) == nil)
        #expect(AccountMemory(defaults: defaults, userID: me, purpose: .cardPaymentBank).recall(among: accounts) == nil)
    }

    @Test("換一個使用者登入不沿用上一個人的選擇")
    func usersAreIndependent() {
        defaults.removePersistentDomain(forName: suite)
        AccountMemory(defaults: defaults, userID: me, purpose: .quickEntry).remember(savings)
        #expect(AccountMemory(defaults: defaults, userID: UserID("someone-else"), purpose: .quickEntry).recall(among: accounts) == nil)
    }

    @Test("記住的帳戶已不在可選清單(刪除或看不到):當作沒有")
    func staleAccountIsIgnored() {
        defaults.removePersistentDomain(forName: suite)
        AccountMemory(defaults: defaults, userID: me, purpose: .quickEntry).remember(AccountID("deleted"))
        #expect(AccountMemory(defaults: defaults, userID: me, purpose: .quickEntry).recall(among: accounts) == nil)
    }
}
