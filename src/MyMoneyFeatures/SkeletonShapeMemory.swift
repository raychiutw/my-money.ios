import Foundation

/// 記住上一次載入完成時,各區塊有幾張卡、有沒有家庭(#204),骨架屏照它畫,載入後版面不跳動。
///
/// 只記**數量與狀態**,不記任何名稱或金額(隱私)。沒有記錄時由呼叫端給預設。
/// 排法(並排或單欄)另外由 `TileLayoutMemory` 記。
public struct SkeletonShapeMemory {
    private let defaults: UserDefaults
    private let prefix: String

    public init(defaults: UserDefaults = .standard, prefix: String = "skeleton") {
        self.defaults = defaults
        self.prefix = prefix
    }

    public func record(count: Int, for key: String) {
        defaults.set(count, forKey: "\(prefix).count.\(key)")
    }

    /// 記下的張數;沒有記錄是 `default`。最多 `limit`(骨架不要比一個畫面還長),最少 0。
    public func count(for key: String, default fallback: Int, limit: Int = 4) -> Int {
        let stored = defaults.object(forKey: "\(prefix).count.\(key)") as? Int ?? fallback
        return min(max(stored, 0), limit)
    }

    public func record(flag: Bool, for key: String) {
        defaults.set(flag, forKey: "\(prefix).flag.\(key)")
    }

    /// 記下的旗標;沒有記錄是 `nil`。
    public func flag(for key: String) -> Bool? {
        defaults.object(forKey: "\(prefix).flag.\(key)") as? Bool
    }
}
