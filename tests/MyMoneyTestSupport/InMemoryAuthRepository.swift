import MyMoneyDomain

/// 不連網路的登入、登出與刪除帳號:登入不開登入視窗,直接以第一位成員登入(UI 測試的登入鈕就是這樣進入 app)。
public actor InMemoryAuthRepository: AuthRepository {
    /// 可以登入的一個人。
    public struct Member: Sendable {
        public let user: User

        public init(user: User) {
            self.user = user
        }

        /// 這個人登入後的 session(權杖是假值)。
        public var session: Session {
            Session(
                user: user,
                tokens: SessionTokens(
                    access: "in-memory-access-\(user.id.rawValue)", refresh: "in-memory-refresh-\(user.id.rawValue)",
                    accessExpiresAt: nil
                )
            )
        }
    }

    private let members: [Member]
    private let gate: Gate?
    private let signInError: (any Error)?
    private let deletionError: RepositoryError?
    private let signsInBiometric: Bool

    /// 每次 `signIn` 是不是開註冊(依呼叫順序)。
    public private(set) var signInRequests: [Bool] = []
    /// `signOut` 撤銷過的更新權杖(依呼叫順序)。
    public private(set) var revokedRefreshTokens: [String] = []

    /// - Parameter gate: 給了就在回應前停住，直到測試放行(登入與登出都會停)。
    /// - Parameter signInError: 給了就讓 `signIn` 失敗;`CancellationError` 代表使用者關掉登入視窗。
    /// - Parameter deletionError: 給了就讓 `deleteAccount` 失敗(後端拒絕)。
    /// - Parameter signsInBiometric: 登入結果當作使用者按了「用 Face ID 登入」(#357)。
    public init(
        members: [Member], gate: Gate? = nil, signInError: (any Error)? = nil, deletionError: RepositoryError? = nil,
        signsInBiometric: Bool = false
    ) {
        self.signsInBiometric = signsInBiometric
        self.members = members
        self.gate = gate
        self.signInError = signInError
        self.deletionError = deletionError
    }

    public func signIn(registering: Bool) async throws -> SignInResult {
        signInRequests.append(registering)
        await gate?.pass()
        if let signInError { throw signInError }
        guard let member = members.first else { throw RepositoryError.rejected("Email 或密碼錯誤") }
        return SignInResult(session: member.session, biometric: signsInBiometric)
    }

    /// 跟 `signIn` 一樣以第一位成員登入(同一個 `gate` 與 `signInError`),不開系統的 passkey 視窗。
    public func signInWithPasskey() async throws -> Session {
        await gate?.pass()
        if let signInError { throw signInError }
        guard let member = members.first else { throw RepositoryError.rejected("找不到對應的 Passkey 憑證") }
        return member.session
    }

    public func signOut(_ session: Session) async {
        await gate?.pass()
        revokedRefreshTokens.append(session.tokens.refresh)
    }

    public func deleteAccount() async throws {
        await gate?.pass()
        if let deletionError { throw deletionError }
    }
}

extension InMemoryAuthRepository.Member {
    /// 畫面 model 測試與 UI 測試共用的家庭成員。
    public static let sample = InMemoryAuthRepository.Member(
        user: User(id: UserID("in-memory-member-1"), email: "family@example.com", name: "小明")
    )
}
