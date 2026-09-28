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

    @Test("代墊統計:GET /households/advances 解讀成每位成員的累計代墊、已報銷、待報銷與兩份明細")
    func advancesDecodeSummaryAndItems() async throws {
        try stub.reply(status: 200, fixture: "households-advances-after-reimburse.json")

        let advances = try await repository.advances()

        #expect(stub.requests.first?.url == stub.baseURL.appending(path: "households/advances"))
        let mine = try #require(advances.first)
        #expect(advances.count == 1)
        #expect(mine.memberID == me)
        #expect(mine.memberName == "iOS 測試帳號")
        #expect(mine.totalAdvanced == Money(250))
        #expect(mine.totalReimbursed == Money(100))
        #expect(mine.pendingReimbursement == Money(150))
        #expect(!mine.isSettled)
        #expect(mine.advanceItems == [AdvanceItem(
            id: TransactionID("0c25bc66-98b6-4c63-861d-b26d795421f2"), date: CalendarDay(year: 2026, month: 9, day: 28),
            category: .dining, note: "全家晚餐", amount: Money(250), accountName: "iOS 測試皮夾", accountKind: .cash
        )])
        #expect(mine.reimbursementItems == [ReimbursementItem(
            id: TransactionID("ff606182-d7d5-4f33-962d-f55429b681a6"), date: CalendarDay(year: 2026, month: 9, day: 28),
            amount: Money(100), note: "iOS 測試報銷 (來自家庭基金 iOS 家庭共同基金)", accountName: "iOS 測試存款"
        )])
    }

    @Test("代墊統計附上每位成員的可收款帳戶，只有名稱和類型(b1382f4);舊的回應沒有這個欄位時是空的")
    func advancesDecodeReceivingAccounts() async throws {
        try stub.reply(status: 200, fixture: "households-advances-with-receiving.json")

        let mine = try #require(try await repository.advances().first)

        #expect(mine.pendingReimbursement == Money(150))
        #expect(mine.receivingAccounts == [
            ReceivingAccount(id: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"), name: "iOS 測試存款", kind: .bank),
            ReceivingAccount(id: AccountID("0fa1efa6-9789-4040-9fe7-22ef3be11b3c"), name: "iOS 測試皮夾", kind: .cash),
        ])

        try stub.reply(status: 200, fixture: "households-advances-after-reimburse.json")
        #expect(try #require(try await repository.advances().first).receivingAccounts.isEmpty)
    }

    @Test("代墊統計：沒有家庭群組時是空的")
    func advancesWithoutHousehold() async throws {
        try stub.reply(status: 200, fixture: "households-advances-no-household.json")

        #expect(try await repository.advances().isEmpty)
    }

    @Test("撥款報銷:POST /households/reimburse 送收款成員、撥款的共同基金、收款帳戶、金額、台灣日期與備註")
    func reimburseSendsBodyAndReturnsMessage() async throws {
        try stub.reply(status: 200, fixture: "households-reimburse.json")

        let message = try await repository.reimburse(Reimbursement(
            memberID: me,
            fromAccountID: AccountID("c70d655c-0238-4bd7-ba83-92e165437e87"),
            toAccountID: AccountID("f4d3074a-4df6-4c98-bd90-bc6f2af91a37"),
            amount: Money(100),
            date: CalendarDay(year: 2026, month: 9, day: 28),
            note: "iOS 測試報銷"
        ))

        #expect(message == "成功從共同基金撥款報銷 NT$ 100 給 iOS 測試帳號！")
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url == stub.baseURL.appending(path: "households/reimburse"))
        let json = try body(request)
        #expect(json["target_user_id"] as? String == me.rawValue)
        #expect(json["from_account_id"] as? String == "c70d655c-0238-4bd7-ba83-92e165437e87")
        #expect(json["to_account_id"] as? String == "f4d3074a-4df6-4c98-bd90-bc6f2af91a37")
        #expect(json["amount"] as? Int == 100)
        #expect(json["date"] as? String == "2026-09-28")
        #expect(json["note"] as? String == "iOS 測試報銷")
    }

    @Test("撥款報銷的錯誤原樣傳遞")
    func reimburseRejected() async throws {
        try stub.reply(status: 400, fixture: "households-reimburse-not-joint.json")

        await #expect(throws: RepositoryError.rejected("撥款帳戶必須為家庭共同基金公帳 (公用帳戶)")) {
            try await repository.reimburse(Reimbursement(
                memberID: me, fromAccountID: AccountID("a"), toAccountID: AccountID("b"), amount: Money(1),
                date: CalendarDay(year: 2026, month: 9, day: 28), note: ""
            ))
        }
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
