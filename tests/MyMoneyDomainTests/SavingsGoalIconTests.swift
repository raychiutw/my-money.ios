import MyMoneyDomain
import Testing

@Suite("儲蓄目標的圖示(上游 efd5064)")
struct SavingsGoalIconTests {
    @Test("12 款預設圖示,順序與上游相同,第一個是預設")
    func allCases() {
        #expect(SavingsGoalIcon.allCases.map(\.rawValue) == [
            "target", "plane", "home", "car", "gem", "laptop", "baby", "graduation-cap", "heart-pulse", "palmtree", "backpack", "palette",
        ])
        #expect(SavingsGoalIcon.default == .target)
    }

    @Test("代號原樣解讀", arguments: SavingsGoalIcon.allCases)
    func keys(icon: SavingsGoalIcon) {
        #expect(SavingsGoalIcon(wire: icon.rawValue) == icon)
    }

    @Test("舊資料的 emoji 依上游的對照表轉成代號", arguments: [
        ("🎯", SavingsGoalIcon.target), ("✈️", .plane), ("🏠", .home), ("🚗", .car), ("💍", .gem), ("💻", .laptop), ("👶", .baby),
        ("🎓", .graduationCap), ("🏥", .heartPulse), ("🏖️", .palmtree), ("🏝️", .palmtree), ("🌴", .palmtree), ("🎒", .backpack),
        ("👜", .backpack), ("🎨", .palette),
    ])
    func legacyEmoji(emoji: String, expected: SavingsGoalIcon) {
        #expect(SavingsGoalIcon(wire: emoji) == expected)
    }

    @Test("沒有、空字串或認不得的字串都是預設的目標圖示", arguments: [nil, "", "  ", "🦄", "rocket"] as [String?])
    func unknownIsDefault(wire: String?) {
        #expect(SavingsGoalIcon(wire: wire) == .target)
    }
}
