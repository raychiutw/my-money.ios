import Foundation

/// 記住的視角(#220):選過的視角記在 UserDefaults，下次沿用;預設全部。
/// 總覽、預測、週期收支、統計、帳戶各用自己的 key，互不影響。
package struct ScopeMemory<Scope: RawRepresentable & CaseIterable> where Scope.RawValue == String {
    let defaults: UserDefaults
    let key: String

    package init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    /// 儲存的值看不懂(或沒存過)時回到第一個選項「全部」。
    package func load() -> Scope {
        defaults.string(forKey: key).flatMap(Scope.init(rawValue:)) ?? Scope.allCases.first!
    }

    /// 值和目前讀得到的一樣就不寫:`@Observable` model 在 `init` 裡賦值也會觸發 `didSet`，建立 model 不該有寫入的副作用。
    package func save(_ scope: Scope) {
        guard load().rawValue != scope.rawValue else { return }
        defaults.set(scope.rawValue, forKey: key)
    }
}
