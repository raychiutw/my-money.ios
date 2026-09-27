import Foundation
import MyMoneyDomain

/// `/forecast` 的 URLSession 實作。這支 API 是 camelCase。
public struct LiveForecastRepository: ForecastRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func forecast() async throws -> CashFlowForecast {
        let dto: ForecastDTO = try await client.get("/forecast")
        return CashFlowForecast(
            dailyBalances: try dto.dailyBalances.map {
                DailyBalance(date: try Self.day($0.date), balance: Money($0.balance))
            },
            minBalance: Money(dto.minBalance),
            // 餘額一直沒有低於起始餘額時，後端的 `minDate` 是空字串。
            minDate: CalendarDay(iso: dto.minDate),
            willOverdraft: dto.willOverdraft,
            events: try dto.events.map { try $0.event() }
        )
    }

    public func checkPurchase(_ amount: Money) async throws -> PurchaseCheck {
        let dto: PurchaseCheckDTO = try await client.send("POST", "/forecast/purchase-check", body: ["amount": amount.amount])
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

    func event() throws -> ForecastEvent {
        guard let type = TransactionType(rawValue: type) else { throw RepositoryError.unreadableResponse }
        return ForecastEvent(date: try LiveForecastRepository.day(date), name: name, type: type, amount: Money(amount))
    }
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
