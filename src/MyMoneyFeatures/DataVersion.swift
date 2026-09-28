import Observation

/// 資料版本：任何新增、修改、刪除成功後遞增;各畫面 model 看到版本改變就重新抓資料。
///
/// 跨畫面刷新只靠這個機制(spec #3「Session 與跨畫面狀態」,ADR-0002)。每個 session 一份。
@MainActor
@Observable
public final class DataVersion {
    public private(set) var value = 0

    public init() {}

    public func bump() {
        value += 1
    }
}
