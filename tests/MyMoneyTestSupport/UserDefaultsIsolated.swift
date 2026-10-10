import Foundation

extension UserDefaults {
    /// 每次都是全新、互不影響的 UserDefaults(視角記憶、骨架形狀記憶不會在測試之間汙染 `.standard`)。
    public static func isolated() -> UserDefaults {
        let suite = "MyMoneyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
