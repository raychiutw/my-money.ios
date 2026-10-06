/// 儲蓄目標的圖示:12 款預設,raw value 是後端 `emoji` 欄位存的圖示代號(上游 efd5064)。
public enum SavingsGoalIcon: String, CaseIterable, Hashable, Sendable {
    case target
    case plane
    case home
    case car
    case gem
    case laptop
    case baby
    case graduationCap = "graduation-cap"
    case heartPulse = "heart-pulse"
    case palmtree
    case backpack
    case palette

    /// 沒有圖示或認不得時的圖示,也是建立時的預設。
    public static let `default` = SavingsGoalIcon.target

    /// 解讀後端的值:代號直接用;資料庫裡舊的 emoji 依上游前端的對照表轉成代號;沒有、空白或認不得的一律是預設圖示。
    public init(wire: String?) {
        let value = wire?.trimmingCharacters(in: .whitespaces) ?? ""
        self = SavingsGoalIcon(rawValue: value) ?? Self.legacyEmoji[value] ?? .default
    }

    private static let legacyEmoji: [String: SavingsGoalIcon] = [
        "🎯": .target, "✈️": .plane, "🏠": .home, "🚗": .car, "💍": .gem, "💻": .laptop, "👶": .baby, "🎓": .graduationCap,
        "🏥": .heartPulse, "🏖️": .palmtree, "🏝️": .palmtree, "🌴": .palmtree, "🎒": .backpack, "👜": .backpack, "🎨": .palette,
    ]
}
