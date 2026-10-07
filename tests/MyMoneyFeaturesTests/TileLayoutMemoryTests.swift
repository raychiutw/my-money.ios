import Foundation
import MyMoneyFeatures
import Testing

/// 骨架屏跟著實際版面(#201):記住上一次載入完成時數字磚是並排還是單欄,骨架用同一種。
@Suite("數字磚排法的記憶(骨架屏用)")
struct TileLayoutMemoryTests {
    private func memory() -> TileLayoutMemory {
        let suite = "TileLayoutMemoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return TileLayoutMemory(defaults: defaults)
    }

    @Test("沒有記錄:骨架沒有依據,回傳 nil")
    func nothingRecorded() {
        #expect(memory().singleColumn(forWidth: 402, sizeKey: "large") == nil)
    }

    @Test("記錄了單欄:同樣的寬度與字級就用單欄;記錄並排就用並排", arguments: [true, false])
    func sameConditions(single: Bool) {
        let memory = memory()
        memory.record(isSingleColumn: single, width: 402, sizeKey: "large")

        #expect(memory.singleColumn(forWidth: 402, sizeKey: "large") == single)
        #expect(memory.singleColumn(forWidth: 402.5, sizeKey: "large") == single, "差 1pt 以內算同一個寬度")
    }

    @Test("寬度或字級改變(旋轉、換字級、iPad 視窗):記錄過期,不採用")
    func conditionsChanged() {
        let memory = memory()
        memory.record(isSingleColumn: true, width: 402, sizeKey: "large")

        #expect(memory.singleColumn(forWidth: 874, sizeKey: "large") == nil)
        #expect(memory.singleColumn(forWidth: 402, sizeKey: "accessibility5") == nil)
    }

    @Test("寬度還不知道(畫面剛出現、還沒量到):字級相同就先用記錄")
    func widthUnknownYet() {
        let memory = memory()
        memory.record(isSingleColumn: true, width: 402, sizeKey: "large")

        #expect(memory.singleColumn(forWidth: nil, sizeKey: "large") == true)
        #expect(memory.singleColumn(forWidth: nil, sizeKey: "accessibility5") == nil)
    }

    @Test("新的記錄取代舊的")
    func latestWins() {
        let memory = memory()
        memory.record(isSingleColumn: true, width: 402, sizeKey: "large")
        memory.record(isSingleColumn: false, width: 874, sizeKey: "large")

        #expect(memory.singleColumn(forWidth: 874, sizeKey: "large") == false)
        #expect(memory.singleColumn(forWidth: 402, sizeKey: "large") == nil)
    }
}
