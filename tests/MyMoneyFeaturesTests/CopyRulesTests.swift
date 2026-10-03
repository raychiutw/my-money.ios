import Foundation
import Testing

/// 文案標點(#157 逐頁 HIG 審查發現「預計餘額會跌破 0,請及早調整」用了半形逗號):
/// 掃描 `src/` 的字串常值，中文句子裡的逗號要用全形「，」。
@Suite("文案規則:中文句子用全形標點")
struct CopyRulesTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "src")

    @Test("字串常值裡的中文句子沒有半形逗號")
    func noHalfWidthCommaInChineseCopy() throws {
        // 字串常值裡「中文字或數字 + 半形逗號 + 中文字」。Regex 不是 Sendable，不能放 static。
        let halfWidthComma = /"[^"\n]*[\u{4E00}-\u{9FFF}0-9],\s?[\u{4E00}-\u{9FFF}][^"\n]*"/
        let enumerator = try #require(FileManager.default.enumerator(at: Self.sourceRoot, includingPropertiesForKeys: nil))
        var violations: [String] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                if line.contains(halfWidthComma) {
                    violations.append("\(file.lastPathComponent):\(index + 1) \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(violations.isEmpty, "中文文案要用全形「，」:\n\(violations.joined(separator: "\n"))")
    }
}
