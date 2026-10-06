import Foundation
import MyMoneyDomain

// 總覽的組成一行、信用卡待繳磚的明細與功能入口格(#178)。
// 數字全是後端的值(CLAUDE.md「規則」);這裡只把它們排成要給人看、給 VoiceOver 念的文字。

extension OverviewModel {
    /// 淨可用餘額底下的一行組成，例如「現金 $1,500 ＋ 活存帳戶 $50,000 − 信用卡待繳 $28,500」;載入前是 `nil`。
    public var compositionText: String? { compositionParts?.joined(separator: " ") }

    /// 組成拆成三段(現金、＋活存帳戶、−信用卡待繳):一行放不下時畫面一段一行，不在字中間折斷。
    public var compositionParts: [String]? {
        guard let summary else { return nil }
        let due = (totalCardDue ?? .zero).formatted()
        return [
            "\(Terms.cash) \(summary.cashTotal.formatted())",
            "＋ \(Terms.bankAccount) \(summary.bankBalanceTotal.formatted())",
            "− 信用卡待繳 \(due)",
        ]
    }

    /// 組成一行的 VoiceOver 念法,例如「現金 1,500 元，加活存帳戶 50,000 元，減信用卡待繳 28,500 元」。
    public var compositionSpokenText: String? {
        guard let summary else { return nil }
        let due = (totalCardDue ?? .zero).spokenText
        return "\(Terms.cash) \(summary.cashTotal.spokenText)，加\(Terms.bankAccount) \(summary.bankBalanceTotal.spokenText)，減信用卡待繳 \(due)"
    }

    // MARK: 信用卡待繳磚的明細

    /// 「N 張卡」加「最近 N 日繳」;沒有信用卡寫「沒有信用卡」。最近的繳款日只看有待繳款的卡。
    var cardTileDetails: [String] {
        guard !creditCards.isEmpty else { return ["沒有信用卡"] }
        return ["\(creditCards.count) 張卡"] + (nearestDueDay.map { ["最近 \($0) 日繳"] } ?? [])
    }

    var cardTileSpokenDetails: String {
        guard !creditCards.isEmpty else { return "沒有信用卡" }
        return ["\(creditCards.count) 張信用卡", nearestDueDay.map { "最近 \($0) 日繳款" }].compactMap { $0 }.joined(separator: "，")
    }

    /// 有待繳款的信用卡裡,從今天算起最近的繳款日(每月幾日):今天(含)以後最小的一天,都過了就是下個月最小的一天。
    private var nearestDueDay: Int? {
        let days = creditCards.filter { $0.totalDue > .zero }.compactMap(\.paymentDueDay)
        return days.filter { $0 >= today().day }.min() ?? days.min()
    }

    // MARK: 功能入口

    /// 3 個功能入口,順序固定(tab 已有的功能不放,#196):週期收支、儲蓄目標、現金流預測;每格一個關鍵數字。
    /// 資料還沒有或那一項載入失敗時 `value` 是 `nil`。
    public var entries: [OverviewEntry] {
        let amortization = summary?.monthlyAmortization
        return [
            OverviewEntry(
                .recurring, title: "週期收支", symbolName: "arrow.triangle.2.circlepath",
                value: amortization.map { "每月平均 \($0.formatted())" },
                spokenValue: amortization.map { "\(Terms.expenseAmortization) \($0.spokenText)" }
            ),
            goalsEntry,
            forecastEntry,
        ]
    }

    /// 儲蓄目標:已存金額合計加整體達成率(跟儲蓄目標頁同一個算法);還沒有目標寫「尚無目標」。
    private var goalsEntry: OverviewEntry {
        func make(_ value: String?, spoken: String? = nil) -> OverviewEntry {
            OverviewEntry(.goals, title: "儲蓄目標", symbolName: "target", value: value, spokenValue: spoken ?? value)
        }
        guard let goals else { return make(nil) }
        guard !goals.isEmpty else { return make("尚無目標") }
        let totals = SavingsGoalTotals(goals)
        return make(
            "已存 \(totals.saved.formatted())・\(totals.overallRateText)",
            spoken: "已存 \(totals.saved.spokenText)，整體達成率 \(totals.overallRateText)"
        )
    }

    /// 現金流預測:後端算好的最低餘額與發生日;會透支用警示色。
    private var forecastEntry: OverviewEntry {
        guard let forecast else {
            return OverviewEntry(.forecast, title: "現金流預測", symbolName: "chart.line.uptrend.xyaxis", value: nil)
        }
        let date = forecast.minDate?.text(today: today(), locale: locale)
        return OverviewEntry(
            .forecast, title: "現金流預測", symbolName: "chart.line.uptrend.xyaxis",
            value: (["最低 \(forecast.minBalance.formatted())"] + [date].compactMap { $0 }).joined(separator: "・"),
            spokenValue: (["最低 \(forecast.minBalance.spokenText)"] + [date].compactMap { $0 }).joined(separator: "，"),
            isWarning: forecast.willOverdraft
        )
    }
}

extension OverviewEntry {
    fileprivate init(
        _ destination: Destination, title: String, symbolName: String, value: String?, spokenValue: String? = nil,
        isWarning: Bool = false
    ) {
        self.init(
            destination: destination, title: title, symbolName: symbolName, value: value, spokenValue: spokenValue ?? value,
            isWarning: isWarning
        )
    }
}

extension Money {
    /// 帶正負號的金額,例如 `+$45,000`、`−$1,250`;0 不帶號。
    func formatted(sign: String) -> String {
        self == .zero ? formatted() : "\(sign)\(Money(abs(amount)).formatted())"
    }
}

// MARK: 接下來 30 天(#189)

extension OverviewModel {
    /// 首頁「接下來 30 天」最多列幾筆。
    public static let upcomingLimit = 5

    /// 後端預測裡最近的幾筆預定收支(含已繳的，已繳的變淡);跟著首頁的視角。預測沒有資料(載入失敗)時是空的，這一區不顯示。
    public var upcomingEvents: [UpcomingEvent] {
        guard let forecast else { return [] }
        return forecast.events.prefix(Self.upcomingLimit).map { event in
            let date = event.date.text(today: today(), locale: locale)
            let ownership = OwnershipName.title(isShared: event.isShared)
            var spoken = [event.name, date, ownership, "\(event.type == .income ? "收入" : "支出") \(event.amount.spokenText)"]
            if event.isSettled { spoken.append("已繳，不計入預測") }
            return UpcomingEvent(
                event: event, dateText: date, subtitle: event.isSettled ? "\(ownership)・已繳" : ownership,
                amountText: event.amount.formatted(sign: event.type == .income ? "+" : "−"),
                spokenText: spoken.joined(separator: "，")
            )
        }
    }
}
