import Foundation
import MyMoneyDomain

// 總覽的組成一行、信用卡待繳磚的明細與功能入口格(#178)。
// 數字全是後端的值(CLAUDE.md「規則」);這裡只把它們排成要給人看、給 VoiceOver 念的文字。

extension OverviewModel {
    /// 淨可用餘額底下的一行組成,例如「現金 $1,500 ＋ 活存帳戶 $50,000 − 信用卡待繳 $28,500」;載入前是 `nil`。
    public var compositionText: String? {
        guard let summary else { return nil }
        let due = (totalCardDue ?? .zero).formatted()
        return "\(Terms.cash) \(summary.cashTotal.formatted()) ＋ \(Terms.bankAccount) \(summary.bankBalanceTotal.formatted()) − 信用卡待繳 \(due)"
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

    /// 8 個功能入口,順序固定;每格一個關鍵數字。資料還沒有或那一項載入失敗時 `value` 是 `nil`。
    public var entries: [OverviewEntry] {
        let accountCount = cashWallets.count + bankAccounts.count + creditCards.count
        let due = totalCardDue
        let amortization = summary?.monthlyAmortization
        return [
            OverviewEntry(
                .ledger, title: Terms.ledger, symbolName: "list.bullet.rectangle",
                value: monthTransactionCount.map { "本月 \($0) 筆" }
            ),
            OverviewEntry(.accounts, title: "帳戶", symbolName: "building.columns", value: summary == nil ? nil : "\(accountCount) 個帳戶"),
            OverviewEntry(
                .creditCards, title: "信用卡", symbolName: "creditcard",
                value: due.map { "待繳 \($0.formatted())" }, spokenValue: due.map { "待繳 \($0.spokenText)" },
                isWarning: (due ?? .zero) > .zero
            ),
            householdEntry,
            OverviewEntry(
                .statistics, title: "統計", symbolName: "chart.bar",
                value: summary == nil ? nil : "\(CalendarMonth(today()).month) 月支出 \(monthExpense.formatted())",
                spokenValue: summary == nil ? nil : "\(CalendarMonth(today()).month) 月支出 \(monthExpense.spokenText)"
            ),
            OverviewEntry(
                .recurring, title: "週期收支", symbolName: "arrow.triangle.2.circlepath",
                value: amortization.map { "每月平均 \($0.formatted())" },
                spokenValue: amortization.map { "\(Terms.expenseAmortization) \($0.spokenText)" }
            ),
            goalsEntry,
            forecastEntry,
        ]
    }

    /// 家庭:剛好兩位成員有公帳代墊時,誰轉多少給誰(跟統計頁、家庭頁同一個分攤建議);個人私帳視角沒有數字。
    private var householdEntry: OverviewEntry {
        func make(_ value: String?, spoken: String? = nil) -> OverviewEntry {
            OverviewEntry(.household, title: "家庭", symbolName: "person.2", value: value, spokenValue: spoken ?? value)
        }
        guard scope != .personal, let shares = householdShares, let settlement = StatisticsModel.settlement(for: shares) else {
            return make(nil)
        }
        guard let transfer = settlement.transfer else { return make("兩人一樣多") }
        return make(
            "\(transfer.from)轉給\(transfer.to) \(transfer.amount.formatted())",
            spoken: "\(transfer.from)轉給\(transfer.to) \(transfer.amount.spokenText)"
        )
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
