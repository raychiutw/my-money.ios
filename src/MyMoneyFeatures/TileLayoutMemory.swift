import Foundation

/// 記住上一次載入完成時,數字磚是並排還是單欄(#201):骨架屏用同一種排法,資料回來時版面不跳動。
///
/// 欄數取決於實際內容的寬度(`TileColumns`:最寬那格放不進三分之一就整排單欄),骨架的佔位字猜不準,
/// 所以改成記住真實結果。只記「並排或單欄」,不記任何金額;連同判斷時的寬度與字級一起存,
/// 條件改變(旋轉、換字級、iPad 視窗大小)時記錄過期、不採用。
public struct TileLayoutMemory {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "overview.tileLayout") {
        self.defaults = defaults
        self.key = key
    }

    public func record(isSingleColumn: Bool, width: Double, sizeKey: String) {
        defaults.set(["single": isSingleColumn, "width": width, "size": sizeKey] as [String: Any], forKey: key)
    }

    /// 骨架要用的排法;沒有記錄或記錄過期時是 `nil`(骨架退回預設佔位,由 `TileColumns` 自己算)。
    /// `width` 還沒量到(畫面剛出現)時,字級相同就先用記錄,量到之後再比對。
    public func singleColumn(forWidth width: Double?, sizeKey: String) -> Bool? {
        guard
            let stored = defaults.dictionary(forKey: key), let single = stored["single"] as? Bool,
            let storedWidth = stored["width"] as? Double, stored["size"] as? String == sizeKey
        else { return nil }
        if let width, abs(width - storedWidth) > 1 { return nil }
        return single
    }
}
