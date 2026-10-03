import Foundation
import Testing

/// 字級一律用系統的文字樣式、跟著系統字級縮放(#156、DESIGN.md「字型與數字」):
/// 掃描 `src/` 的 Swift 檔，禁止寫死字級、縮小文字、封頂 Dynamic Type 的寫法，例外只能是下面清單裡有理由的幾處。
/// 之後新加的畫面寫了這些寫法，這個測試會失敗。
@Suite("字級規則:只用文字樣式、不縮小、不封頂")
struct TypographyRulesTests {
    private struct Rule {
        let name: String
        let pattern: String
        let why: String
    }

    private static let rules = [
        Rule(name: "寫死的 pt 字級", pattern: ".system(size:", why: "用文字樣式(.body、.headline…)，不寫死 pt 值"),
        Rule(name: "寫死大小的 UIFont", pattern: "systemFont(ofSize:", why: "UIKit 的字要用 UIFontMetrics 縮放，並列入例外清單"),
        Rule(name: "縮小文字", pattern: "minimumScaleFactor", why: "放不下改版面(換行、堆疊)，不要把字縮小"),
        Rule(name: "封頂的 Dynamic Type", pattern: ".dynamicTypeSize(...", why: "字級不封頂；放不下改版面"),
    ]

    /// 例外:檔名加規則名稱，理由寫在這裡。新增例外要有理由。
    private static let exceptions: [String: String] = [
        "SegmentedPicker.swift|寫死大小的 UIFont": "用 UIFontMetrics(.subheadline)縮放，系統字級改變時重設；15 是 HIG 字級表 Subhead 的預設大小",
        "AccountEditorView.swift|封頂的 Dynamic Type": "帳戶代表色色塊 32pt 圓圈裡的勾勾是裝飾符號，圓圈固定大小(#78)",
    ]

    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "src")

    private func swiftFiles() throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: Self.sourceRoot, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("src/ 沒有寫死字級、縮小文字或封頂 Dynamic Type 的寫法(例外清單除外)")
    func noForbiddenPatterns() throws {
        var violations: [String] = []
        for file in try swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // 註解與文件不算(說明為什麼不用)。
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                for rule in Self.rules where line.contains(rule.pattern) {
                    if Self.exceptions["\(file.lastPathComponent)|\(rule.name)"] != nil { continue }
                    violations.append("\(file.lastPathComponent):\(index + 1) \(rule.name)(\(rule.why))")
                }
            }
        }
        #expect(violations.isEmpty, "違反字級規則:\n\(violations.joined(separator: "\n"))")
    }

    @Test("例外清單裡的每一項都還用得到(用不到就刪掉)")
    func exceptionsAreStillNeeded() throws {
        for key in Self.exceptions.keys {
            let parts = key.split(separator: "|").map(String.init)
            let rule = try #require(Self.rules.first { $0.name == parts[1] })
            let file = try #require(try swiftFiles().first { $0.lastPathComponent == parts[0] }, "找不到 \(parts[0])")
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.contains(rule.pattern), "\(key) 已經沒有這個寫法，請把它從例外清單拿掉")
        }
    }
}
