import Foundation
import MyMoneyDomain

/// 不連網路的帳號安全:記下登出的裝置與修改密碼的請求。跟後端一樣,修改密碼成功後只剩這台裝置。
public actor InMemoryAccountSecurityRepository: AccountSecurityRepository {
    private var stored: [LoginSession]
    private var failure: RepositoryError?
    private let gate: Gate?

    public private(set) var signedOutIDs: [LoginSessionID] = []
    public private(set) var signedOutOthersCount = 0
    public private(set) var passwordChanges: [(current: String, new: String)] = []

    /// - Parameter failure: 給了就讓每個請求都失敗(後端拒絕)。
    /// - Parameter gate: 給了就在修改密碼回應前停住,直到測試放行。
    public init(sessions: [LoginSession], failure: RepositoryError? = nil, gate: Gate? = nil) {
        stored = sessions
        self.failure = failure
        self.gate = gate
    }

    /// 之後的請求都失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }

    /// 這支 iPhone(目前這台)。
    public static let thisPhone = LoginSession(
        id: LoginSessionID("sample-this-phone"), client: "ios", deviceName: "iPhone · My Money App",
        createdAt: Date(timeIntervalSince1970: 1_794_000_000), lastUsedAt: Date(timeIntervalSince1970: 1_794_716_050),
        isCurrent: true
    )

    /// 另一台用 web 登入的電腦。
    public static let webBrowser = LoginSession(
        id: LoginSessionID("sample-web"), client: "web", deviceName: "Chrome · macOS",
        createdAt: Date(timeIntervalSince1970: 1_793_000_000), lastUsedAt: Date(timeIntervalSince1970: 1_794_800_000),
        isCurrent: false
    )

    /// 這支 iPhone 與一台 web(web 最近使用,排在前面,跟後端一樣依最後使用時間排序)。
    public static func sample(gate: Gate? = nil) -> InMemoryAccountSecurityRepository {
        InMemoryAccountSecurityRepository(sessions: [webBrowser, thisPhone], gate: gate)
    }

    public func loginSessions() async throws -> [LoginSession] {
        if let failure { throw failure }
        return stored
    }

    public func signOut(_ id: LoginSessionID) async throws {
        if let failure { throw failure }
        signedOutIDs.append(id)
        stored.removeAll { $0.id == id }
    }

    public func signOutOtherSessions() async throws {
        if let failure { throw failure }
        signedOutOthersCount += 1
        stored.removeAll { !$0.isCurrent }
    }

    public func changePassword(current: String, new: String) async throws -> String {
        await gate?.pass()
        if let failure { throw failure }
        passwordChanges.append((current, new))
        stored.removeAll { !$0.isCurrent }
        return "密碼已更新，其他裝置已登出"
    }
}
