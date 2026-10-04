import Foundation
import MyMoneyFeatures
import Testing

/// 使用者看得見的詞只有一套(#181、`docs/parity.md` 用詞偏離、CONTEXT.md):
/// 掃描 `src/` 的**字串常值**(註解不算，註解常引用上游原文)，出現舊詞就失敗。
/// 用詞更名分三張票逐步套用(expand–contract，#185～#187):當時沒套用到的地方先列在例外清單，清完就刪;現在例外是空的。
@Suite("用詞規則:字串常值裡沒有舊詞")
struct TermsRulesTests {
    /// 舊詞 → 新詞(說明用)。
    private static let oldTerms: [(old: String, replacement: String)] = [
        ("銀行存款", "活存帳戶"),
        ("現金錢包", "現金"),
        ("交易記錄", "收支明細"),
        ("交易明細", "收支明細"),
        ("交易", "記帳(功能的名字)或收支明細(記錄本身)"),
        ("分攤平滑", "週期支出每月平均"),
        ("待報銷代墊總額", "待報銷總額"),
        ("一鍵報銷", "報銷沖帳"),
    ]

    /// 例外:`檔名|舊詞` → 理由與票號。用詞更名(#185、#186、#187)的例外都清完了，現在是空的;
    /// 新增例外要寫理由(例如引用上游原文)，不可以拿來放行還沒改的舊詞。
    private static let exceptions: [String: String] = [:]

    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "src")

    /// 一行裡所有字串常值的內容;`//` 之後(不在字串裡)是註解，略過。
    private static func literals(in line: Substring) -> [String] {
        var result: [String] = []
        var current = ""
        var inString = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if inString {
                if character == "\\" {
                    current.append(character)
                    index = line.index(after: index)
                    if index < line.endIndex { current.append(line[index]) }
                } else if character == "\"" {
                    result.append(current)
                    current = ""
                    inString = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inString = true
            } else if character == "/", line[line.index(after: index)...].hasPrefix("/") {
                break
            }
            index = line.index(after: index)
        }
        return result
    }

    private struct Hit: Hashable {
        let file: String
        let term: String
        var key: String { "\(file)|\(term)" }
    }

    private func hits() throws -> [Hit: [String]] {
        let enumerator = try #require(FileManager.default.enumerator(at: Self.sourceRoot, includingPropertiesForKeys: nil))
        var found: [Hit: [String]] = [:]
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                for literal in Self.literals(in: line) {
                    for (old, _) in Self.oldTerms where literal.contains(old) {
                        found[Hit(file: file.lastPathComponent, term: old), default: []]
                            .append("\(file.lastPathComponent):\(index + 1) \(literal)")
                    }
                }
            }
        }
        return found
    }

    @Test("字串常值裡沒有舊詞(例外清單除外)")
    func noOldTermsInStringLiterals() throws {
        var violations: [String] = []
        for (hit, places) in try hits() where Self.exceptions[hit.key] == nil {
            let replacement = Self.oldTerms.first { $0.old == hit.term }?.replacement ?? ""
            violations += places.map { "\($0)(「\(hit.term)」改成「\(replacement)」)" }
        }
        #expect(violations.isEmpty, "用了舊詞:\n\(violations.sorted().joined(separator: "\n"))")
    }

    @Test("例外清單裡的每一項都還用得到(用不到就刪掉)")
    func exceptionsAreStillNeeded() throws {
        let present = Set(try hits().keys.map(\.key))
        for key in Self.exceptions.keys {
            #expect(present.contains(key), "例外「\(key)」已經沒有舊詞了，請從清單刪掉")
        }
    }

    @Test("名稱單一來源是新詞，而且沒有舊詞")
    func termsSourceUsesNewWords() {
        let all = [
            Terms.bankAccount, Terms.cash, Terms.ledger, Terms.transactions, Terms.expenseAmortization,
            Terms.incomeAmortization, Terms.monthlyAverage, Terms.pendingReimbursementTotal, Terms.reimburse,
        ]

        #expect(all == ["活存帳戶", "現金", "記帳", "收支明細", "週期支出每月平均", "週期收入每月平均", "換算每月平均", "待報銷總額", "報銷沖帳"])
        for term in all {
            for (old, _) in Self.oldTerms { #expect(!term.contains(old), "\(term) 含舊詞 \(old)") }
        }
    }

    @Test("掃描器會讀字串常值、略過註解與行尾註解")
    func lexerReadsLiteralsNotComments() {
        #expect(Self.literals(in: #"let a = "銀行存款" + "x\"y" // 現金錢包"#) == ["銀行存款", #"x\"y"#])
        #expect(Self.literals(in: "// \"交易記錄\"").isEmpty)
        #expect(Self.literals(in: #"Text("交易(\(count))")"#) == [#"交易(\(count))"#])
    }
}
