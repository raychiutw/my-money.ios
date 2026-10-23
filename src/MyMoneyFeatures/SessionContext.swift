import Foundation
import MyMoneyDomain

/// 這個登入 session 的畫面 model 共同的建構脈絡(#227):資料版本、UserDefaults、地區、「今天」。
///
/// 以前每個 model 的 initializer 各自收這幾個參數(順序也不一致);現在 composition root 建一份，model 收它一個參數，
/// 之後多一個共同欄位(例如 clock)只改這裡。`permissions` 與 `currentUser` 不放進來——只有部分 model 需要。
/// 不是單例，也不放進 `Environment`:由 `App`(唯一的 composition root)建立後以 initializer 傳入(ADR-0001、ADR-0002)。
@MainActor
public struct SessionContext {
    public let dataVersion: DataVersion
    public let defaults: UserDefaults
    public let locale: Locale
    public let today: () -> CalendarDay
    /// 登入的人;帳戶記憶的 key 綁它(#273)。測試與預覽可以不給，就不記憶。
    public let userID: UserID?

    /// `locale` 決定日期與月份的格式，預設跟著系統;`today` 決定日期要不要寫年份，預設是台灣時間的今天。
    public init(
        dataVersion: DataVersion = DataVersion(),
        defaults: UserDefaults = .standard,
        locale: Locale = .autoupdatingCurrent,
        today: @escaping () -> CalendarDay = { CalendarDay.today() },
        userID: UserID? = nil
    ) {
        self.userID = userID
        self.dataVersion = dataVersion
        self.defaults = defaults
        self.locale = locale
        self.today = today
    }

    /// 這個登入的人、某個「選帳戶」功能的帳戶記憶(#273);沒有登入的人時是 `nil`(不記憶)。
    public func accountMemory(_ purpose: AccountMemory.Purpose) -> AccountMemory? {
        userID.map { AccountMemory(defaults: defaults, userID: $0, purpose: purpose) }
    }
}
