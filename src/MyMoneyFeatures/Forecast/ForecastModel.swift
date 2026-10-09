import Foundation
import MyMoneyDomain
import Observation

/// 現金流預測頁的 model(parity.md「現金流預測」)。
/// 預測頁的起始餘額(`ForecastModel.startingBalance(of:)`)。
public struct StartingBalance: Equatable, Sendable {
    public let amount: Money
    /// 「現金 $1,750・活存帳戶 $101,200」。
    public let detail: String
    /// 起始餘額比現金加活存帳戶少時的說明;相等時是 `nil`。
    public let note: String?
}

@MainActor
@Observable
public final class ForecastModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var phase: Phase = .loading
    /// 資料回來之前是 `nil`:畫面不會先顯示「安全」或 $0(parity 刻意偏離第 7 項)。
    public private(set) var forecast: CashFlowForecast?

    /// 視角(上游 ADR 0016):預設全部;選過的視角記在 UserDefaults。換視角時購買力試算的結果清掉。
    public var scope: ViewScope {
        didSet {
            defaults.set(scope.rawValue, forKey: Self.scopeKey)
            purchaseCheck = nil
            purchaseError = nil
        }
    }

    public var purchaseAmountText = ""
    public private(set) var purchaseCheck: PurchaseCheck?
    public private(set) var purchaseError: String?
    public private(set) var isChecking = false

    /// 正在送出「已繳」的事件識別碼:送出期間那一筆的圓圈停用，避免連點(上游 ADR 0018)。
    public private(set) var settlingKeys: Set<String> = []
    /// 勾選或取消已繳失敗時，後端的訊息(例如 403 無權限)。
    public private(set) var settleError: String?

    @ObservationIgnored private let repository: any ForecastRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private var loadedVersion: Int?
    @ObservationIgnored private var loadedScope: ViewScope?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let today: () -> CalendarDay

    private static let scopeKey = "forecast.scope"

    /// 骨架屏的預定收支筆數與摘要有沒有「起始餘額」那一組(#204 核對);第一次沒有記錄時 3 筆、有起始餘額。
    public struct SkeletonCounts: Equatable, Sendable {
        public let events: Int
        public let hasStartingBalance: Bool

        public init(events: Int, hasStartingBalance: Bool) {
            self.events = events
            self.hasStartingBalance = hasStartingBalance
        }
    }

    private var skeletonMemory: SkeletonShapeMemory { SkeletonShapeMemory(defaults: defaults, prefix: "skeleton.forecast") }

    public var skeletonCounts: SkeletonCounts {
        SkeletonCounts(
            events: skeletonMemory.count(for: "events", default: 3, limit: 6),
            hasStartingBalance: skeletonMemory.flag(for: "startingBalance") ?? true
        )
    }

    /// `locale` 決定日期的格式，預設跟著系統;`today` 決定日期要不要寫年份。
    public init(
        repository: any ForecastRepository,
        dataVersion: DataVersion,
        defaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        self.dataVersion = dataVersion
        self.defaults = defaults
        self.locale = locale
        self.today = today
        scope = defaults.string(forKey: Self.scopeKey).flatMap(ViewScope.init(rawValue:)) ?? .all
    }

    /// 預測頁描述期程的文字(後端的期程是 `ForecastHorizon.days` 天)。
    public static var chartTitle: String { "未來 \(ForecastHorizon.days) 天逐日餘額" }
    public static var eventsCountTitle: String { "未來 \(ForecastHorizon.days) 天的預定收支" }
    public static var noEventsText: String { "未來 \(ForecastHorizon.days) 天沒有預定收支" }

    /// 預測裡的日期(預定收支日、逐日餘額),例如「10月5日」,不是今年的加上年份(DESIGN.md「日期」)。
    public func dateText(_ day: CalendarDay) -> String {
        day.text(today: today(), locale: locale)
    }

    /// 預定收支列左邊的次要文字「日期・歸屬」，例如「10月5日・家庭公帳」(#155)。
    public func subtitle(of event: ForecastEvent) -> String {
        "\(dateText(event.date))・\(OwnershipName.title(isShared: event.isShared))"
    }

    /// 預定收支列右邊金額下面的資產帳戶名稱;沒有帳戶就沒有這一行。
    public func accountText(of event: ForecastEvent) -> String? { event.accountName }

    /// VoiceOver 念的整句，例如「房租,10月5日,家庭公帳,帳戶 洋蔥玉山-共同基金,支出 12,000 元」。
    public func spokenText(of event: ForecastEvent) -> String {
        var parts = [event.name, dateText(event.date), OwnershipName.title(isShared: event.isShared)]
        if let account = event.accountName { parts.append("帳戶 \(account)") }
        parts.append("\(event.type == .income ? "收入" : "支出") \(event.amount.spokenText)")
        if event.isSettled { parts.append("已繳，不計入預測") }
        return parts.joined(separator: ",")
    }

    /// 已繳事件的說明文字(畫面上不只靠變淡與刪除線);未繳的事件沒有。
    public func settledNote(of event: ForecastEvent) -> String? {
        event.isSettled ? "已繳(不計入預測)" : nil
    }

    /// 預測頁的「起始餘額」:主數字加「現金」「活存帳戶」兩個數字(都是後端的值,不寫成算式,因為先扣掉的信用卡待繳款讓三者不成加總)。
    /// 舊回應或缺少任何一個數字時是 `nil`,畫面不顯示這一組。
    public func startingBalance(of forecast: CashFlowForecast) -> StartingBalance? {
        guard let start = forecast.startingBalance, let cash = forecast.cashTotal, let bank = forecast.bankTotal else { return nil }
        return StartingBalance(
            amount: start,
            detail: "\(Terms.cash) \(cash.formatted())・\(Terms.bankAccount) \(bank.formatted())",
            // 後端已把繳款日不在未來 \(ForecastHorizon.days) 天內(或沒設繳款日)的信用卡待繳款先扣掉;兩者不相等才需要說明。
            note: start == cash + bank ? nil : "已先扣掉繳款日不在未來 \(ForecastHorizon.days) 天內的信用卡待繳款"
        )
    }

    /// 最低餘額發生的日期;沒有變動時是「無變動」。
    public func minDateText(of forecast: CashFlowForecast) -> String {
        guard let minDate = forecast.minDate else { return "無變動" }
        return dateText(minDate)
    }

    public func load() async {
        let version = dataVersion.value
        let scope = scope
        do {
            let loaded = try await repository.forecast(scope: scope)
            // 被取消(換了視角)或已經過期的結果不套用。
            guard !Task.isCancelled, scope == self.scope else { return }
            forecast = loaded
            loadedVersion = version
            loadedScope = scope
            skeletonMemory.record(count: loaded.events.count, for: "events")
            skeletonMemory.record(flag: loaded.startingBalance != nil, for: "startingBalance")
            phase = .loaded
        } catch {
            // 被取消的載入不是載入失敗;下一次載入會更新畫面。
            guard !Task.isCancelled, scope == self.scope else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// 標示或取消一筆事件的「已繳」(上游 ADR 0018):送出成功後重抓預測——已繳事件從逐日餘額、最低餘額排除由後端算，
    /// client 不重算。沒有識別碼或不能勾選的事件、正在送出的事件都不送。
    public func setSettled(_ settled: Bool, for event: ForecastEvent) async {
        guard let key = event.key, event.canSettle, !settlingKeys.contains(key) else { return }
        settleError = nil
        settlingKeys.insert(key)
        defer { settlingKeys.remove(key) }
        do {
            try await repository.setSettled(settled, forEventKey: key)
        } catch {
            let message = error.localizedDescription
            settleError = message.isEmpty ? "更新已繳狀態失敗" : message
            return
        }
        // 遞增資料版本:總覽「接下來 60 天」等其他畫面也要重抓(#189);先遞增再 `load()`，這頁記下的版本就是新的，不會再重抓一次。
        dataVersion.bump()
        await load()
    }

    /// 使用者看過「無法更新已繳狀態」的提示之後清掉。
    public func clearSettleError() {
        settleError = nil
    }

    /// 資料版本或視角在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value || loadedScope != scope else { return }
        await load()
    }

    /// 購買力試算;接受任何正整數(parity 刻意偏離第 4 項)。
    public func checkPurchase() async {
        purchaseError = nil
        guard let amount = Money(wholeNumber: purchaseAmountText), amount > .zero else {
            purchaseCheck = nil
            purchaseError = "請輸入有效的購買金額"
            return
        }
        isChecking = true
        defer { isChecking = false }
        let scope = scope
        do {
            let check = try await repository.checkPurchase(amount, scope: scope)
            // 試算期間換了視角:舊視角的結論不套用。
            guard scope == self.scope else { return }
            purchaseCheck = check
        } catch {
            guard scope == self.scope else { return }
            purchaseCheck = nil
            let message = error.localizedDescription
            purchaseError = message.isEmpty ? "檢查失敗" : message
        }
    }
}

extension CashFlowForecast {
    public var riskTitle: String { willOverdraft ? "存在透支風險" : "現金流充裕安全" }
}

extension PurchaseCheck {
    public var title: String {
        switch verdict {
        case .safe: "放心購買"
        case .caution: "審慎評估"
        case .danger: "不建議購買"
        }
    }

    public var message: String {
        switch verdict {
        case .safe:
            "花 \(amount.formatted()) 之後，未來 \(ForecastHorizon.days) 天的最低餘額仍有 \(minBalance.formatted()),也不影響儲蓄目標的每月預留。"
        case .caution:
            "花 \(amount.formatted()) 不會透支，但會壓縮儲蓄目標的每月預留(可能影響\(affectedGoalNames.joined(separator: "、")))。建議延後購買或調降金額。"
        case .danger:
            "花 \(amount.formatted()) 之後，未來 \(ForecastHorizon.days) 天的餘額最低會跌到 \(minBalance.formatted())。"
        }
    }
}
