import Foundation
import MyMoneyDomain
import MyMoneyFeatures
import MyMoneyTestSupport
import Testing

@MainActor
@Suite("家庭群組")
struct HouseholdTests {
    private let dataVersion = DataVersion()

    private func loaded(_ repository: InMemoryHouseholdRepository) async -> HouseholdModel {
        let model = HouseholdModel(repository: repository, dataVersion: dataVersion)
        await model.load()
        return model
    }

    private func member(_ name: String, _ role: HouseholdRole) -> HouseholdMember {
        HouseholdMember(
            userID: UserID(name), name: name, email: "\(name)@example.com", role: role,
            joinedAt: try! Date("2026-09-27T21:20:20Z", strategy: .iso8601)
        )
    }

    @Test("還沒加入家庭群組")
    func withoutHousehold() async {
        let model = await loaded(InMemoryHouseholdRepository(household: nil))

        #expect(model.phase == .loaded)
        #expect(model.household == nil)
    }

    @Test("建立家庭群組：名稱必填")
    func createRequiresName() async {
        let repository = InMemoryHouseholdRepository(household: nil)
        let model = await loaded(repository)

        model.createName = "   "
        #expect(!model.canCreate)
        await model.create()

        #expect(await repository.createdNames.isEmpty)
    }

    @Test("建立成功後資料版本遞增，並顯示新的家庭群組(我是管理員)")
    func create() async throws {
        let repository = InMemoryHouseholdRepository(household: nil)
        let model = await loaded(repository)
        model.createName = " 我們家 "

        await model.create()

        #expect(await repository.createdNames == ["我們家"])
        #expect(dataVersion.value == 1)
        let household = try #require(model.household)
        #expect(household.name == "我們家")
        #expect(household.myRole == .admin)
    }

    @Test("用邀請碼加入：錯誤時顯示後端的訊息")
    func joinFailure() async {
        let repository = InMemoryHouseholdRepository(household: nil)
        await repository.fail(with: .rejected("邀請碼無效或已過期"))
        let model = HouseholdModel(repository: repository, dataVersion: dataVersion)
        model.joinCode = "FAM-0000"

        await model.join()

        #expect(model.alertMessage == "邀請碼無效或已過期")
        #expect(dataVersion.value == 0)
    }

    @Test("用邀請碼加入成功後資料版本遞增;邀請碼必填")
    func join() async {
        let repository = InMemoryHouseholdRepository(household: nil)
        let model = await loaded(repository)

        model.joinCode = " "
        #expect(!model.canJoin)

        model.joinCode = " fam-ab12 "
        await model.join()

        #expect(await repository.joinedCodes == ["fam-ab12"])
        #expect(dataVersion.value == 1)
    }

    @Test("我的角色與成員人數")
    func summary() async throws {
        let model = await loaded(InMemoryHouseholdRepository.sample())
        let household = try #require(model.household)

        #expect(household.myRole.title == "管理員")
        #expect(HouseholdRole.member.title == "一般成員")
        #expect(model.memberCountText == "2 位成員")
    }

    @Test("每按一次邀請，就產生一組新的邀請碼")
    func inviteEveryTime() async throws {
        let repository = InMemoryHouseholdRepository.sample()
        let model = await loaded(repository)

        await model.invite()
        let first = try #require(model.invitation)
        await model.invite()
        let second = try #require(model.invitation)

        #expect(first.code != second.code)
        #expect(await repository.inviteCount == 2)
    }

    @Test("只有管理員看得到「移除」,而且只出現在一般成員上")
    func canRemove() async throws {
        let adminView = await loaded(InMemoryHouseholdRepository.sample())
        let members = try #require(adminView.household?.members)

        #expect(members.map { adminView.canRemove($0) } == [false, true])

        let memberView = await loaded(InMemoryHouseholdRepository.sample(myRole: .member))
        #expect(memberView.household?.members.contains { memberView.canRemove($0) } == false)
    }

    @Test("移除與離開的確認文字")
    func confirmations() async {
        let model = await loaded(InMemoryHouseholdRepository.sample())

        #expect(model.removeConfirmation(for: member("小美", .member)) == "確定要將「小美」移出家庭嗎？")
        #expect(model.leaveConfirmation == "確定要退出這個家庭嗎？退出後將無法查看這個家庭的家庭公帳。")
    }

    @Test("移除成員後資料版本遞增")
    func remove() async throws {
        let repository = InMemoryHouseholdRepository.sample()
        let model = await loaded(repository)
        let mei = try #require(model.household?.members.last)

        await model.remove(mei)

        #expect(await repository.removedIDs == [mei.userID])
        #expect(dataVersion.value == 1)
        #expect(model.household?.members.count == 1)
    }

    @Test("離開後資料版本遞增，回到還沒加入的畫面")
    func leave() async {
        let repository = InMemoryHouseholdRepository.sample()
        let model = await loaded(repository)

        await model.leave()

        #expect(await repository.leaveCount == 1)
        #expect(dataVersion.value == 1)
        #expect(model.household == nil)
    }

    @Test("名稱開頭字", arguments: [("小美", "小"), ("alice", "A"), ("", "?")])
    func initial(name: String, expected: String) {
        #expect(member(name, .member).initial == expected)
    }

    /// web 直接取 UTC 字串的前 10 個字，台灣時間早上會顯示成前一天(parity 刻意偏離第 29 項)。
    @Test("加入日期換成當地的日期")
    func joinedDate() throws {
        let taipei = try #require(TimeZone(identifier: "Asia/Taipei"))

        #expect(member("小美", .member).joinedDateText(in: taipei) == "2026/09/28")
    }
}
