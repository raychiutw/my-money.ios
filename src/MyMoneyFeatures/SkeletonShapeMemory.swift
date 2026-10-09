import Foundation

/// 記住上一次載入完成時,各區塊有幾張卡、有沒有家庭(#204),骨架屏照它畫,載入後版面不跳動。
///
/// 只記**數量與狀態**,不記任何名稱或金額(隱私)。沒有記錄時由呼叫端給預設。
/// 排法(並排或單欄)也記在這裡(`recordArrangement`/`arrangement`):連同判斷時的寬度與字級一起存,條件改變(旋轉、換字級、iPad 視窗大小)就過期。
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

    // MARK: 排法(並排或單欄)

    /// 記下 `key`(例如「tiles」「entries」)這一排實際選到的排法,連同當時的寬度與字級。
    public func recordArrangement(isSingleColumn: Bool, width: Double, sizeKey: String, for key: String) {
        defaults.set(["single": isSingleColumn, "width": width, "size": sizeKey] as [String: Any], forKey: "\(prefix).arrangement.\(key)")
    }

    /// 骨架要用的排法(`true` 是單欄);沒有記錄或記錄過期(字級不同、寬度差超過 1pt)時是 `nil`,骨架退回預設佔位自己算。
    /// `width` 還沒量到(畫面剛出現)時,字級相同就先用記錄。
    public func arrangement(forWidth width: Double?, sizeKey: String, for key: String) -> Bool? {
        guard
            let stored = defaults.dictionary(forKey: "\(prefix).arrangement.\(key)"), let single = stored["single"] as? Bool,
            let storedWidth = stored["width"] as? Double, stored["size"] as? String == sizeKey
        else { return nil }
        if let width, abs(width - storedWidth) > 1 { return nil }
        return single
    }
}
