import Foundation

/// 家庭裡的角色。raw value 是後端的 `role`。
public enum HouseholdRole: String, Hashable, Sendable {
    /// 家庭管理員：建立家庭的人，可以邀請、移除一般成員，也可以替任何成員從共同基金撥款報銷(上游 ADR 0013)。
    case admin
    case member
}

/// 家庭成員名冊的一個人。
public struct HouseholdMember: Hashable, Sendable, Identifiable {
    public let userID: UserID
    public let name: String
    public let email: String
    public let role: HouseholdRole
    public let joinedAt: Date

    public init(userID: UserID, name: String, email: String, role: HouseholdRole, joinedAt: Date) {
        self.userID = userID
        self.name = name
        self.email = email
        self.role = role
        self.joinedAt = joinedAt
    }

    public var id: UserID { userID }
}

/// 家庭(Household):每個人同時最多屬於一個。
public struct Household: Hashable, Sendable {
    public let name: String
    public let myRole: HouseholdRole
    /// 家庭管理員在前，同角色依加入時間排序(後端的順序)。
    public let members: [HouseholdMember]

    public init(name: String, myRole: HouseholdRole, members: [HouseholdMember]) {
        self.name = name
        self.myRole = myRole
        self.members = members
    }
}

/// 邀請碼，格式是 `FAM-XXXX`,7 天內有效。
public struct HouseholdInvitation: Hashable, Sendable, Identifiable {
    public let code: String
    public let expiresAt: Date

    public init(code: String, expiresAt: Date) {
        self.code = code
        self.expiresAt = expiresAt
    }

    public var id: String { code }
}

/// 家庭(`/households`)。
public protocol HouseholdRepository: Sendable {
    /// 我目前的家庭;還沒加入時是 `nil`。
    func current() async throws -> Household?

    /// 建立家庭，我是家庭管理員。
    func create(name: String) async throws

    func join(code: String) async throws

    /// 每次呼叫都產生一組新的邀請碼;只有家庭管理員可以，一般成員回 403。
    func invite() async throws -> HouseholdInvitation

    /// 離開;最後一位成員離開時，後端會刪掉整個家庭。
    func leave() async throws

    /// 只有家庭管理員可以移除一般成員。
    func removeMember(_ userID: UserID) async throws

    /// 每位成員的家庭公帳代墊統計與明細;還沒加入家庭時是空的。
    func advances() async throws -> [HouseholdAdvance]

    /// 從家庭共同基金撥款報銷代墊款。回傳後端的訊息;一般成員替其他成員撥款時回 403。
    func reimburse(_ reimbursement: Reimbursement) async throws -> String
}
