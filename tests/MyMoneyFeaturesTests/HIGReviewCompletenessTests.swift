import Foundation
import Testing

/// 逐頁 HIG 審查文件的守門(#157):截圖巡覽拍的每一頁都要在審查文件裡有一節,而且每個「缺失」都有處理(修正的說明或票號)。
/// 新增畫面時要同時補審查紀錄，審查才不會做一次就過期。
@Suite("HIG 逐頁審查文件:每一頁都審查過、每個缺失都有處理")
struct HIGReviewCompletenessTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 截圖巡覽拍的頁面名稱:`capturing: "x"` 與 `captureScrolling("x")`。
    private func tourPages() throws -> [String] {
        let source = try String(contentsOf: Self.root.appending(path: "tests/MyMoneyUITests/ScreenTourUITests.swift"), encoding: .utf8)
        let patterns = [#"capturing: "([a-z0-9-]+)""#, #"captureScrolling\("([a-z0-9-]+)"\)"#]
        var pages: [String] = []
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let range = Range(match.range(at: 1), in: source), !pages.contains(String(source[range])) {
                    pages.append(String(source[range]))
                }
            }
        }
        return pages
    }

    private func reviewText() throws -> String {
        let directory = Self.root.appending(path: "docs/research")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let review = try #require(
            files.first { $0.lastPathComponent.hasSuffix("apple-hig-page-by-page-review.md") },
            "docs/research/ 沒有 *-apple-hig-page-by-page-review.md"
        )
        return try String(contentsOf: review, encoding: .utf8)
    }

    @Test("截圖巡覽有 28 頁，審查文件每一頁都有一節(標題寫頁面名稱)")
    func everyTourPageHasASection() throws {
        let pages = try tourPages()
        #expect(pages.count >= 28, "截圖巡覽的頁面清單讀不到或變少了:\(pages)")
        let text = try reviewText()
        let missing = pages.filter { !text.contains("### `\($0)`") }
        #expect(missing.isEmpty, "審查文件缺少這些頁面的一節(### `頁面名稱`):\(missing)")
    }

    @Test("每個「缺失」都有處理:修正的說明(已修正)或後續票號(#數字)")
    func everyDefectHasAnOutcome() throws {
        let rows = try reviewText().split(separator: "\n").filter { $0.contains("❌") && $0.hasPrefix("|") }
        let unresolved = rows.filter { row in
            row.range(of: #"#\d+"#, options: .regularExpression) == nil && !row.contains("已修正")
        }
        #expect(unresolved.isEmpty, "這些缺失沒有處理(要有票號或「已修正」):\n\(unresolved.joined(separator: "\n"))")
    }

    @Test("每一列都有結論:符合、刻意偏離、缺失、需要真機確認")
    func everyRowHasAVerdict() throws {
        let text = try reviewText()
        let verdicts = ["✅", "⚠️", "❌", "📱"]
        let tableRows = text.split(separator: "\n").filter { $0.hasPrefix("| ") && !$0.hasPrefix("| ---") && !$0.hasPrefix("| 議題") }
        let missing = tableRows.filter { row in !verdicts.contains { row.contains($0) } }
        #expect(missing.isEmpty, "這些列沒有結論符號:\n\(missing.joined(separator: "\n"))")
    }
}
