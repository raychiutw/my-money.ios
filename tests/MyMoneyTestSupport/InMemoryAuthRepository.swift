import MyMoneyDomain

/// 不連網路的登入與註冊：只認得建立時給的，以及之後註冊的家庭成員;回應的訊息照後端的字串。
public actor InMemoryAuthRepository: AuthRepository {
    /// 可以登入的一個人。
    public struct Member: Sendable {
        public let email: String
        public let password: String
        public let user: User

        public init(email: String, password: String, user: User) {
            self.email = email
            self.password = password
            self.user = user
        }
    }

    private var members: [Member]
    private let gate: Gate?

    /// 透過 `register` 建立的帳號的 email,依註冊順序。
    public private(set) var registeredEmails: [String] = []

    /// - Parameter gate: 給了就在回應前停住，直到測試放行。
    public init(members: [Member], gate: Gate? = nil) {
        self.members = members
        self.gate = gate
    }

    public func login(email: String, password: String) async throws -> Session {
        await gate?.pass()
        guard let member = members.first(where: { $0.email == email && $0.password == password }) else {
            throw RepositoryError.rejected("Email 或密碼錯誤")
        }
        return Self.session(for: member)
    }

    public func register(name: String, email: String, password: String) async throws -> Session {
        await gate?.pass()
        guard !members.contains(where: { $0.email == email }) else {
            throw RepositoryError.rejected("此 Email 已被使用")
        }
        let member = Member(
            email: email,
            password: password,
            user: User(id: UserID("in-memory-member-\(members.count + 1)"), email: email, name: name)
        )
        members.append(member)
        registeredEmails.append(email)
        return Self.session(for: member)
    }

    private static func session(for member: Member) -> Session {
        Session(token: "in-memory-token-\(member.user.id.rawValue)", user: member.user)
    }
}

extension InMemoryAuthRepository.Member {
    /// 畫面 model 測試與 UI 測試共用的家庭成員。
    public static let sample = InMemoryAuthRepository.Member(
        email: "family@example.com",
        password: "secret123",
        user: User(id: UserID("in-memory-member-1"), email: "family@example.com", name: "小明")
    )
}
