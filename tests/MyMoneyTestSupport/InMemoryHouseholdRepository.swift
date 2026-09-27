import Foundation
import MyMoneyDomain

/// 不連網路的家庭群組，記下建立、加入、邀請、移除、離開。
public actor InMemoryHouseholdRepository: HouseholdRepository {
    private var stored: Household?
    private var failure: RepositoryError?

    public private(set) var createdNames: [String] = []
    public private(set) var joinedCodes: [String] = []
    public private(set) var removedIDs: [UserID] = []
    public private(set) var inviteCount = 0
    public private(set) var leaveCount = 0

    public init(household: Household?) {
        stored = household
    }

    /// 「我們家」:小明(管理員，就是登入的範例帳號)和小美(一般成員)。
    public static func sample(myRole: HouseholdRole = .admin) -> InMemoryHouseholdRepository {
        let joined = Date(timeIntervalSince1970: 1_790_000_000)
        return InMemoryHouseholdRepository(household: Household(name: "我們家", myRole: myRole, members: [
            me(role: .admin, joinedAt: joined),
            HouseholdMember(
                userID: UserID("sample-mei"), name: "小美", email: "mei@example.com", role: .member,
                joinedAt: joined.addingTimeInterval(86_400)
            ),
        ]))
    }

    public func current() async throws -> Household? {
        if let failure { throw failure }
        return stored
    }

    /// 跟後端一樣：建立的人是管理員，也是唯一的成員。
    public func create(name: String) async throws {
        if let failure { throw failure }
        createdNames.append(name)
        stored = Household(name: name, myRole: .admin, members: [Self.me(role: .admin, joinedAt: .now)])
    }

    public func join(code: String) async throws {
        if let failure { throw failure }
        joinedCodes.append(code)
        stored = Household(name: "家人的家", myRole: .member, members: [Self.me(role: .member, joinedAt: .now)])
    }

    public func invite() async throws -> HouseholdInvitation {
        if let failure { throw failure }
        inviteCount += 1
        return HouseholdInvitation(code: "FAM-TST\(inviteCount)", expiresAt: .now.addingTimeInterval(7 * 86_400))
    }

    public func leave() async throws {
        if let failure { throw failure }
        leaveCount += 1
        stored = nil
    }

    public func removeMember(_ userID: UserID) async throws {
        if let failure { throw failure }
        removedIDs.append(userID)
        if let household = stored {
            stored = Household(name: household.name, myRole: household.myRole, members: household.members.filter { $0.userID != userID })
        }
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    /// 登入的範例帳號。
    private static func me(role: HouseholdRole, joinedAt: Date) -> HouseholdMember {
        let user = InMemoryAuthRepository.Member.sample.user
        return HouseholdMember(userID: user.id, name: user.name, email: user.email, role: role, joinedAt: joinedAt)
    }
}
