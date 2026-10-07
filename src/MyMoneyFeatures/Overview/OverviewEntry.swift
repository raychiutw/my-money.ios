import Foundation
import MyMoneyDomain

/// 總覽的一格功能入口(#178):圖示、名稱加一個關鍵數字;點了進該功能。
public struct OverviewEntry: Identifiable, Hashable, Sendable {
    /// 入口去哪裡。畫面依它決定是切 tab 還是在總覽的導覽堆疊 push。
    public enum Destination: String, CaseIterable, Hashable, Sendable {
        case recurring
        case goals
        case forecast
    }

    public let destination: Destination
    public let title: String
    public let symbolName: String
    /// 關鍵數字;資料還沒有(或這一項載入失敗)時是 `nil`,格子只剩名稱。
    public let value: String?
    /// VoiceOver 念的關鍵數字(金額念成「X 元」)。
    public let spokenValue: String?
    /// 用警示色(有待繳的信用卡、會透支的預測)。
    public let isWarning: Bool

    public var id: Destination { destination }

    /// 「名稱,關鍵數字」;沒有數字時只念名稱。
    public var spokenText: String {
        [title, spokenValue].compactMap { $0 }.joined(separator: "，")
    }
}

/// 首頁「接下來 60 天」的一列預定收支(#189):後端預測的事件加上要給人看、給 VoiceOver 念的文字。
public struct UpcomingEvent: Identifiable, Hashable, Sendable {
    public let event: ForecastEvent
    public let dateText: String
    public let subtitle: String
    public let amountText: String
    public let spokenText: String

    public var id: String { event.key ?? "\(event.date.iso)-\(event.name)" }
    public var isIncome: Bool { event.type == .income }
    /// 有識別碼而且後端說這個人能勾選，才有勾選圓圈。
    public var isSettleable: Bool { event.key != nil && event.canSettle }
    /// 勾選圓圈的 VoiceOver 標籤。
    public var checkLabel: String { event.isSettled ? "取消已繳" : "標示為已繳" }
}
