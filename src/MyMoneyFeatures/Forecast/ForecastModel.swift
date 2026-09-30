import Foundation
import MyMoneyDomain
import Observation

/// 現金流預測頁的 model(parity.md「現金流預測」)。
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

    public var purchaseAmountText = ""
    public private(set) var purchaseCheck: PurchaseCheck?
    public private(set) var purchaseError: String?
    public private(set) var isChecking = false

    @ObservationIgnored private let repository: any ForecastRepository
    @ObservationIgnored public let dataVersion: DataVersion
    @ObservationIgnored private var loadedVersion: Int?
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private let today: () -> CalendarDay

    /// `locale` 決定日期的格式，預設跟著系統;`today` 決定日期要不要寫年份。
    public init(
        repository: any ForecastRepository,
        dataVersion: DataVersion,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay = { CalendarDay.today() }
    ) {
        self.repository = repository
        self.dataVersion = dataVersion
        self.locale = locale
        self.today = today
    }

    /// 預測裡的日期(預定收支日、逐日餘額),例如「10月5日」,不是今年的加上年份(DESIGN.md「日期」)。
    public func dateText(_ day: CalendarDay) -> String {
        day.text(today: today(), locale: locale)
    }

    /// 最低餘額發生的日期;沒有變動時是「無變動」。
    public func minDateText(of forecast: CashFlowForecast) -> String {
        guard let minDate = forecast.minDate else { return "無變動" }
        return dateText(minDate)
    }

    public func load() async {
        let version = dataVersion.value
        do {
            forecast = try await repository.forecast()
            loadedVersion = version
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// 資料版本在上一次載入之後改變過，才重新載入。
    public func refreshIfStale() async {
        guard loadedVersion != dataVersion.value else { return }
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
        do {
            purchaseCheck = try await repository.checkPurchase(amount)
        } catch {
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
            "花 \(amount.formatted()) 之後，未來 30 天的最低餘額仍有 \(minBalance.formatted()),也不影響儲蓄目標的每月預留。"
        case .caution:
            "花 \(amount.formatted()) 不會透支，但會壓縮儲蓄目標的每月預留(可能影響\(affectedGoalNames.joined(separator: "、")))。建議延後購買或調降金額。"
        case .danger:
            "花 \(amount.formatted()) 之後，未來 30 天的餘額最低會跌到 \(minBalance.formatted())。"
        }
    }
}
