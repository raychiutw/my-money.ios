import Foundation
import MyMoneyDomain

/// `/forecast` 的 URLSession 實作。這支 API 是 camelCase。
public struct LiveForecastRepository: ForecastRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// 一律明確帶 `scope`(`all` 也帶)，不依賴後端的預設範圍。
    public func forecast(scope: ViewScope) async throws -> CashFlowForecast {
        let dto: ForecastDTO = try await client.get("/forecast", query: [URLQueryItem(name: "scope", value: scope.rawValue)])
        return CashFlowForecast(
            dailyBalances: try dto.dailyBalances.map {
                DailyBalance(date: try Self.day($0.date), balance: Money($0.balance))
            },
            minBalance: Money(dto.minBalance),
            // 上游 `e138bd9` 起 `minDate` 永遠有值(沒有變動時是第一天);更早的版本是空字串，仍然當作沒有。
            minDate: CalendarDay(iso: dto.minDate),
            willOverdraft: dto.willOverdraft,
            events: try dto.events.map { try $0.event() }
        )
    }

    public func checkPurchase(_ amount: Money, scope: ViewScope) async throws -> PurchaseCheck {
        let dto: PurchaseCheckDTO = try await client.send(
            "POST", "/forecast/purchase-check", body: PurchaseCheckBody(amount: amount.amount, scope: scope.rawValue)
        )
        guard let verdict = PurchaseVerdict(rawValue: dto.verdict) else { throw RepositoryError.unreadableResponse }
        return PurchaseCheck(
            amount: Money(dto.amount),
            verdict: verdict,
            minBalance: Money(dto.minBalance),
            affectedGoalNames: dto.affectedGoals.map(\.name)
        )
    }

    fileprivate static func day(_ iso: String) throws -> CalendarDay {
        guard let day = CalendarDay(iso: iso) else { throw RepositoryError.unreadableResponse }
        return day
    }
}

private struct ForecastDTO: Decodable {
    struct Day: Decodable {
        let date: String
        let balance: Decimal
    }

    let dailyBalances: [Day]
    let minBalance: Decimal
    let minDate: String
    let willOverdraft: Bool
    let events: [EventDTO]
}

private struct EventDTO: Decodable {
    let date: String
    let name: String
    let type: String
    let amount: Decimal
    /// 上游 ADR 0016 起的欄位(0/1，snake_case);舊的回應沒有，當成個人私帳。
    let isShared: Int?
    let accountName: String?

    enum CodingKeys: String, CodingKey {
        case date, name, type, amount
        case isShared = "is_shared"
        case accountName = "account_name"
    }

    func event() throws -> ForecastEvent {
        guard let type = TransactionType(rawValue: type) else { throw RepositoryError.unreadableResponse }
        return ForecastEvent(
            date: try LiveForecastRepository.day(date), name: name, type: type, amount: Money(amount),
            isShared: (isShared ?? 0) != 0, accountName: accountName
        )
    }
}

private struct PurchaseCheckBody: Encodable {
    let amount: Decimal
    let scope: String
}

private struct PurchaseCheckDTO: Decodable {
    struct Goal: Decodable {
        let name: String
    }

    let amount: Decimal
    let verdict: String
    let minBalance: Decimal
    let affectedGoals: [Goal]
}
