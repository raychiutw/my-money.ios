import MyMoneyDomain

/// 透支風險區間(上游 `a68a231`,#316):逐日餘額連續小於 0 的一段。
/// 由逐日餘額在 client 聚合,是顯示用整理(跟區間最低餘額一樣),餘額本身是後端算好的,不是業務規則重算。
public struct OverdraftInterval: Hashable, Sendable {
    public let start: CalendarDay
    public let end: CalendarDay
    public let days: Int
    /// 這一段裡的最低餘額(最大資金缺口)與發生日(同值取最早)。
    public let minBalance: Money
    public let minDate: CalendarDay
    /// 區間第一天發生、尚未標示已繳的支出事件名稱(繳卡費、週期支出)。
    public let triggerNames: [String]
    /// 第 0 天(預測第一天)就是負的:顯示「起始可用餘額不足」。
    public let startsNegative: Bool

    public init(
        start: CalendarDay, end: CalendarDay, days: Int, minBalance: Money, minDate: CalendarDay, triggerNames: [String], startsNegative: Bool
    ) {
        self.start = start
        self.end = end
        self.days = days
        self.minBalance = minBalance
        self.minDate = minDate
        self.triggerNames = triggerNames
        self.startsNegative = startsNegative
    }
}

extension ForecastModel {
    // MARK: 事件累計結餘(#315)

    /// 預定事件列的「結餘 $X」(事件發生後的累計結餘,後端 `running_balance`);舊回應沒有就是 `nil`。
    public func balanceAfterText(of event: ForecastEvent) -> String? {
        event.runningBalance.map { "結餘 \($0.formatted())" }
    }

    /// 事件發生後的累計結餘是負的:列上用警示色。
    public func isOverdrawn(_ event: ForecastEvent) -> Bool {
        (event.runningBalance ?? .zero) < .zero
    }

    // MARK: 透支風險區間(#316)

    /// 整個期程的所有透支區間(不受查詢區間影響,點一段才聚焦);沒有透支是空陣列。
    public var overdraftIntervals: [OverdraftInterval] {
        guard let forecast else { return [] }
        let days = forecast.dailyBalances
        var result: [OverdraftInterval] = []
        var index = 0
        while index < days.count {
            guard days[index].balance < .zero else {
                index += 1
                continue
            }
            var end = index
            while end + 1 < days.count, days[end + 1].balance < .zero { end += 1 }
            let run = days[index...end]
            let low = run.min { $0.balance < $1.balance } ?? run[index]
            let lowest = run.first { $0.balance == low.balance } ?? low
            let start = days[index].date
            result.append(OverdraftInterval(
                start: start, end: days[end].date, days: end - index + 1, minBalance: lowest.balance, minDate: lowest.date,
                triggerNames: forecast.events.filter { $0.date == start && $0.type == .expense && !$0.isSettled }.map(\.name),
                startsNegative: index == 0
            ))
            index = end + 1
        }
        return result
    }

    /// 目前查詢區間剛好等於哪一段透支區間(點過「聚焦」);不是就是 `nil`。
    public var focusedInterval: OverdraftInterval? {
        overdraftIntervals.first { $0.start == rangeStart && $0.end == rangeEnd }
    }

    /// 查詢區間剛好等於這一段(畫面逐列判斷用,不必重算所有區間)。
    public func isFocused(_ interval: OverdraftInterval) -> Bool {
        rangeStart == interval.start && rangeEnd == interval.end
    }

    /// 把查詢區間鎖到這一段透支區間。
    public func focus(on interval: OverdraftInterval) {
        rangeStart = interval.start
        rangeEnd = interval.end
    }

    /// 區間標題,例如「11月3日~11月4日・共 2 天」;單日是「11月3日・共 1 天」。
    public func overdraftTitle(of interval: OverdraftInterval) -> String {
        let range = interval.days == 1 ? dateText(interval.start) : "\(dateText(interval.start))~\(dateText(interval.end))"
        return "\(range)・共 \(interval.days) 天"
    }

    /// 區間下一行:最低餘額與發生日,例如「最低 −$30(11月4日)」。
    public func overdraftDetail(of interval: OverdraftInterval) -> String {
        "最低 \(interval.minBalance.formatted())(\(dateText(interval.minDate)))"
    }

    /// 首日觸發的原因:第 0 天就是負的是「起始可用餘額不足」;否則列出首日的支出事件;都沒有就是 `nil`。
    public func overdraftTrigger(of interval: OverdraftInterval) -> String? {
        if interval.startsNegative { return "起始可用餘額不足" }
        return interval.triggerNames.isEmpty ? nil : "首日支出:" + interval.triggerNames.joined(separator: "、")
    }

    /// 摘要旁的一句話,例如「共 2 段透支(合計 5 天)」;沒有透支是 `nil`。
    public var overdraftSummary: String? {
        let intervals = overdraftIntervals
        guard !intervals.isEmpty else { return nil }
        return "共 \(intervals.count) 段透支(合計 \(intervals.reduce(0) { $0 + $1.days }) 天)"
    }
}
