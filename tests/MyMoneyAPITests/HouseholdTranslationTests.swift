import Foundation
import MyMoneyAPI
import MyMoneyDomain
import Testing

@Suite("家庭群組的翻譯(/households)")
struct HouseholdTranslationTests {
    private let stub = HTTPStub()
    private let session = FakeSessionProvider(token: "fixture-token")
    private let me = UserID("ff646114-6f6b-4a37-9e27-4757868af51d")

    private var repository: LiveHouseholdRepository {
        LiveHouseholdRepository(client: APIClient(baseURL: stub.baseURL, urlSession: stub.urlSession, session: session))
    }

    private func body(_ request: URLRequest?) throws -> [String: Any] {
        let data = try #require(request?.httpBody)
        let json = try JSONSerialization.jsonObject(with: data)
        return try #require(json as? [String: Any])
    }

    @Test("還沒加入家庭群組時是 nil")
    func currentWithoutHousehold() async throws {
        try stub.reply(status: 200, fixture: "households-current-none.json")

        #expect(try await repository.current() == nil)
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "households/current"))
    }

    @Test("家庭群組：名稱、我的角色、成員名冊(加入時間是 UTC)")
    func currentHousehold() async throws {
        try stub.reply(status: 200, fixture: "households-current.json")

        let household = try #require(try await repository.current())

        #expect(household.name == "iOS 測試家庭")
        #expect(household.myRole == .admin)
        #expect(household.members == [HouseholdMember(
            userID: me,
            name: "iOS 測試帳號",
            email: "mymoney-ios-test@example.com",
            role: .admin,
            joinedAt: try Date("2026-09-27T21:20:20Z", strategy: .iso8601)
        )])
    }

    @Test("建立家庭群組:POST /households {name}")
    func create() async throws {
        try stub.reply(status: 201, fixture: "households-create.json")

        try await repository.create(name: "iOS 測試家庭")

        #expect(stub.requests.first?.httpMethod == "POST")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "households"))
        #expect(try body(stub.requests.first)["name"] as? String == "iOS 測試家庭")
    }

    @Test("用邀請碼加入:POST /households/join {code}")
    func join() async throws {
        try stub.reply(status: 404, fixture: "households-join-invalid.json")

        await #expect(throws: RepositoryError.rejected("邀請碼無效或已過期")) {
            try await repository.join(code: "FAM-0000")
        }
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "households/join"))
        #expect(try body(stub.requests.first)["code"] as? String == "FAM-0000")
    }

    @Test("產生邀請碼：每次一組新的，有效期限是 ISO 8601")
    func invite() async throws {
        try stub.reply(status: 200, fixture: "households-invite.json")

        let invitation = try await repository.invite()

        #expect(stub.requests.first?.httpMethod == "POST")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "households/invite"))
        #expect(invitation == HouseholdInvitation(
            code: "FAM-UY7L", expiresAt: try Date("2026-10-04T21:20:25.335Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        ))
    }

    @Test("離開家庭群組:DELETE 只回 {success, message}")
    func leave() async throws {
        try stub.reply(status: 200, fixture: "households-leave.json")

        try await repository.leave()

        #expect(stub.requests.first?.httpMethod == "DELETE")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "households/leave"))
    }

    @Test("移除成員:DELETE /households/members/:userId")
    func removeMember() async throws {
        try stub.reply(status: 400, fixture: "households-remove-self.json")

        await #expect(throws: RepositoryError.rejected("請使用離開家庭功能")) {
            try await repository.removeMember(me)
        }
        #expect(stub.requests.first?.httpMethod == "DELETE")
        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "households/members/\(me.rawValue)"))
    }

    @Test("後端的錯誤原樣傳遞", arguments: [
        ("households-create-missing-name.json", 400, "請輸入家庭名稱"),
        ("households-join-already-member.json", 400, "你已經加入家庭群組，無法重複加入"),
        ("households-leave-none.json", 400, "你未加入任何家庭"),
    ])
    func rejections(fixture: String, status: Int, message: String) async throws {
        try stub.reply(status: status, fixture: fixture)

        await #expect(throws: RepositoryError.rejected(message)) {
            switch fixture {
            case "households-create-missing-name.json": try await repository.create(name: "")
            case "households-join-already-member.json": try await repository.join(code: "FAM-0000")
            default: try await repository.leave()
            }
        }
    }
}
