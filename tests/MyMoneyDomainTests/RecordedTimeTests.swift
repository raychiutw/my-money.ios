import Foundation
import MyMoneyDomain
import Testing

/// 收支的記錄時間(上游 718ace9、#207):後端 `created_at` 是 UTC、沒有時區標記;iOS 轉成台灣時間(UTC+8)的 `HH:mm` 顯示。
@Suite("收支記錄時間")
struct RecordedTimeTests {
    @Test("UTC 轉台灣時間的 HH:mm", arguments: [
        ("2026-09-27 19:57:02", "03:57"),   // 跨日:UTC 的 27 日晚上是台灣 28 日凌晨
        ("2026-10-06 07:27:51", "15:27"),
        ("2026-10-06 16:00:00", "00:00"),   // 整點跨日
        ("2026-10-06 15:59:59", "23:59"),
    ])
    func taipeiClock(utc: String, expected: String) throws {
        let date = try #require(RecordedTime.date(fromBackend: utc))
        #expect(RecordedTime.clockText(of: date) == expected)
    }

    @Test("台灣時間的日期(跨日時跟 created_at 的 UTC 日期不同)")
    func taipeiDay() throws {
        let date = try #require(RecordedTime.date(fromBackend: "2026-09-27 19:57:02"))
        #expect(CalendarDay(date: date) == CalendarDay(year: 2026, month: 9, day: 28))
    }

    @Test("沒有、空白或看不懂的時間是 nil,不壞", arguments: [nil, "", "  ", "yesterday", "2026-13-40 99:99:99"] as [String?])
    func unreadable(value: String?) {
        #expect(RecordedTime.date(fromBackend: value) == nil)
    }

    @Test("也接受 ISO 8601(後端可能的另一種格式)")
    func iso() throws {
        let date = try #require(RecordedTime.date(fromBackend: "2026-10-06T07:27:51Z"))
        #expect(RecordedTime.clockText(of: date) == "15:27")
    }
}
