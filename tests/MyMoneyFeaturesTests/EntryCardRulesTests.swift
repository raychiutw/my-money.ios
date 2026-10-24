import Foundation
import Testing

/// 明細卡內部三排之間沒有分隔線(#305,DESIGN.md「明細卡第三版」);每筆明細之間的線是列表畫的,不在卡裡。
/// SwiftUI 的 Divider 不會出現在 UI 階層,UI 測試量不到,所以掃描原始碼守門。
@Suite("明細卡規則:卡內沒有分隔線")
struct EntryCardRulesTests {
    @Test("EntryCard 的原始碼沒有 Divider")
    func entryCardHasNoDivider() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "src/MyMoneyFeatures/EntryCard.swift")
        let source = try String(contentsOf: file, encoding: .utf8)

        #expect(!source.contains("Divider()"), "卡內三排之間不放分隔線(每筆之間的列線由列表畫)")
    }
}
