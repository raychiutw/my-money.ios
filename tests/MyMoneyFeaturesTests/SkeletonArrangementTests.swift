import Foundation
import MyMoneyFeatures
import Testing

/// 骨架屏跟著實際版面(#201):記住上一次載入完成時數字磚是並排還是單欄,骨架用同一種。
@Suite("骨架屏的排法記憶(並排或單欄,同一個形狀記憶 module)")
struct SkeletonArrangementTests {
    private func memory() -> SkeletonShapeMemory {
        let suite = "SkeletonArrangementTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SkeletonShapeMemory(defaults: defaults)
    }

    @Test("沒有記錄:骨架沒有依據,回傳 nil")
    func nothingRecorded() {
        #expect(memory().arrangement(forWidth: 402, sizeKey: "large", for: "tiles") == nil)
    }

    @Test("記錄了單欄:同樣的寬度與字級就用單欄;記錄並排就用並排", arguments: [true, false])
    func sameConditions(single: Bool) {
        let memory = memory()
        memory.recordArrangement(isSingleColumn: single, width: 402, sizeKey: "large", for: "tiles")

        #expect(memory.arrangement(forWidth: 402, sizeKey: "large", for: "tiles") == single)
        #expect(memory.arrangement(forWidth: 402.5, sizeKey: "large", for: "tiles") == single, "差 1pt 以內算同一個寬度")
    }

    @Test("寬度或字級改變(旋轉、換字級、iPad 視窗):記錄過期,不採用")
    func conditionsChanged() {
        let memory = memory()
        memory.recordArrangement(isSingleColumn: true, width: 402, sizeKey: "large", for: "tiles")

        #expect(memory.arrangement(forWidth: 874, sizeKey: "large", for: "tiles") == nil)
        #expect(memory.arrangement(forWidth: 402, sizeKey: "accessibility5", for: "tiles") == nil)
    }

    @Test("寬度還不知道(畫面剛出現、還沒量到):字級相同就先用記錄")
    func widthUnknownYet() {
        let memory = memory()
        memory.recordArrangement(isSingleColumn: true, width: 402, sizeKey: "large", for: "tiles")

        #expect(memory.arrangement(forWidth: nil, sizeKey: "large", for: "tiles") == true)
        #expect(memory.arrangement(forWidth: nil, sizeKey: "accessibility5", for: "tiles") == nil)
    }

    @Test("新的記錄取代舊的")
    func latestWins() {
        let memory = memory()
        memory.recordArrangement(isSingleColumn: true, width: 402, sizeKey: "large", for: "tiles")
        memory.recordArrangement(isSingleColumn: false, width: 874, sizeKey: "large", for: "tiles")

        #expect(memory.arrangement(forWidth: 874, sizeKey: "large", for: "tiles") == false)
        #expect(memory.arrangement(forWidth: 402, sizeKey: "large", for: "tiles") == nil)
    }
}

@Suite("骨架屏的排法記憶:同一個 module 內各排法互相獨立")
struct SkeletonArrangementKeysTests {
    @Test("數字磚與入口格各自記自己的排法")
    func keysAreIndependent() {
        let suite = "SkeletonArrangementKeysTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let memory = SkeletonShapeMemory(defaults: defaults)

        memory.recordArrangement(isSingleColumn: true, width: 402, sizeKey: "large", for: "tiles")
        memory.recordArrangement(isSingleColumn: false, width: 402, sizeKey: "large", for: "entries")

        #expect(memory.arrangement(forWidth: 402, sizeKey: "large", for: "tiles") == true)
        #expect(memory.arrangement(forWidth: 402, sizeKey: "large", for: "entries") == false)
        #expect(memory.arrangement(forWidth: 402, sizeKey: "large", for: "other") == nil)
    }
}
