import Foundation
import MyMoneyDomain

/// 不連網路的 passkey 管理:建立時不開系統的 passkey 視窗,直接加一筆;記下建立與改名的請求。
public actor InMemoryPasskeyRepository: PasskeyRepository {
    public struct Rename: Equatable, Sendable {
        public let id: PasskeyID
        public let name: String

        public init(id: PasskeyID, name: String) {
            self.id = id
            self.name = name
        }
    }

    private var stored: [Passkey]
    private var failure: (any Error)?
    private let gate: Gate?

    public private(set) var createdNames: [String] = []
    public private(set) var renames: [Rename] = []

    /// - Parameter failure: 給了就讓每個請求都失敗;`CancellationError` 代表使用者關掉系統的 passkey 視窗。
    /// - Parameter gate: 給了就在建立回應前停住,直到測試放行。
    public init(passkeys: [Passkey], failure: (any Error)? = nil, gate: Gate? = nil) {
        stored = passkeys
        self.failure = failure
        self.gate = gate
    }

    /// 之後的請求都失敗。
    public func fail(with error: any Error) {
        failure = error
    }

    /// 這支 iPhone 建立的,還沒用來登入過。
    public static let iPhone = Passkey(
        id: PasskeyID("sample-passkey-iphone"), name: "iPhone", createdAt: Date(timeIntervalSince1970: 1_794_716_050), lastUsedAt: nil
    )

    /// web 在 Mac 上建立的,用過。
    public static let mac = Passkey(
        id: PasskeyID("sample-passkey-mac"), name: "MacBook", createdAt: Date(timeIntervalSince1970: 1_793_000_000),
        lastUsedAt: Date(timeIntervalSince1970: 1_794_800_000)
    )

    /// iPhone 與 Mac(新的在前,跟後端一樣依建立時間排序)。
    public static func sample() -> InMemoryPasskeyRepository {
        InMemoryPasskeyRepository(passkeys: [iPhone, mac])
    }

    public func passkeys() async throws -> [Passkey] {
        if let failure { throw failure }
        return stored
    }

    public func create(name: String) async throws {
        await gate?.pass()
        if let failure { throw failure }
        createdNames.append(name)
        stored.insert(Passkey(id: PasskeyID("in-memory-passkey-\(createdNames.count)"), name: name, createdAt: Date(), lastUsedAt: nil), at: 0)
    }

    public func rename(_ id: PasskeyID, to name: String) async throws {
        if let failure { throw failure }
        renames.append(Rename(id: id, name: name))
        stored = stored.map { $0.id == id ? Passkey(id: $0.id, name: name, createdAt: $0.createdAt, lastUsedAt: $0.lastUsedAt) : $0 }
    }

    public func delete(_ id: PasskeyID) async throws {
        if let failure { throw failure }
        stored.removeAll { $0.id == id }
    }
}
