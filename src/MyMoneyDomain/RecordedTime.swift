import Foundation

/// 收支的記錄時間(上游 718ace9、#207):後端在建立收支時自動記下,回傳的 `created_at` 是 UTC、沒有時區標記
/// (`YYYY-MM-DD HH:mm:ss`);iOS 轉成台灣時間(UTC+8,沒有夏令時間)的 `HH:mm` 顯示,**不自己產生或修改時間**。
public enum RecordedTime {
    /// 解讀後端的 `created_at`;沒有、空白或看不懂時是 `nil`。
    public static func date(fromBackend value: String?) -> Date? {
        guard let text = value?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(identifier: "UTC")
        utc.isLenient = false
        utc.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = utc.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    /// 台灣時間的 `HH:mm`(24 小時制,跟 web 一致),例如「15:27」。
    public static func clockText(of date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = CalendarDay.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// VoiceOver 念的時間(台灣時間,系統的念法),例如「凌晨 3:57」;`nil` 不念。
    public static func spokenText(of date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.timeZone = CalendarDay.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
