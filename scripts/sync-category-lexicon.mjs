#!/usr/bin/env node
// 從上游 onion523/my-money 的 web/src/components/utils.ts 同步「智慧推薦」的關鍵字詞庫,
// 並用上游自己的 recommendCategory 產生對照表,讓 iOS 的推薦跟 web 逐筆一致(docs/parity.md「智慧推薦」)。
//
// 用法:scripts/sync-category-lexicon.mjs <上游 utils.ts 的路徑> <上游 commit>
//   例:gh api "repos/onion523/my-money/contents/web/src/components/utils.ts?ref=97f4789" --jq .content | base64 -d > /tmp/upstream_utils.ts
//       scripts/sync-category-lexicon.mjs /tmp/upstream_utils.ts 97f4789
// 需要 Node 22.18 以上(直接載入 .ts,不需要另外安裝套件)。
//
// 產生兩個檔案,不要手改:
//   src/MyMoneyDomain/Transactions/CategoryLexicon.swift   詞庫(規則順序照上游,每條規則是一串關鍵字)
//   tests/MyMoneyDomainTests/CategoryLexiconGolden.swift   對照表:上游在這些備註上的推薦結果
import { copyFileSync, mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const [source, commit] = process.argv.slice(2)
if (!source || !commit) {
  console.error('用法:sync-category-lexicon.mjs <上游 utils.ts 的路徑> <上游 commit>')
  process.exit(1)
}
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
// Node 只認 .mts/.ts 副檔名才會去掉型別,先複製一份。
const dir = mkdtempSync(join(tmpdir(), 'lexicon-'))
const copy = join(dir, 'upstream_utils.mts')
copyFileSync(source, copy)
const upstream = await import(copy)

const escape = (text) => text.replaceAll('\\', '\\\\').replaceAll('"', '\\"')
const keywordsOf = (rule) => {
  const source = rule.pattern.source
  // 詞庫都是純文字關鍵字用 | 分隔;有正規表示式的特殊字元就代表上游改了寫法,要人工處理。
  if (/[\\^$.*+?()[\]{}]/.test(source)) throw new Error(`規則「${rule.category}」含有正規表示式的特殊字元,請人工確認:${source}`)
  if (!rule.pattern.ignoreCase || rule.pattern.global || rule.pattern.sticky) throw new Error(`規則「${rule.category}」的旗標不是單純的 /i`)
  return source.split('|').map((keyword) => keyword.toLowerCase())
}
const rulesOf = (lexicon) => lexicon.map((rule) => ({ category: rule.category, keywords: keywordsOf(rule) }))
const expense = rulesOf(upstream.EXPENSE_LEXICON)
const income = rulesOf(upstream.INCOME_LEXICON)

const swiftRules = (rules) => rules
  .map((rule) => `        Rule(category: "${escape(rule.category)}", keywords: [\n${rule.keywords.map((keyword) => `            "${escape(keyword)}",\n`).join('')}        ]),\n`)
  .join('')
writeFileSync(join(root, 'src/MyMoneyDomain/Transactions/CategoryLexicon.swift'), `// 由 scripts/sync-category-lexicon.mjs 產生,不要手改。
// 來源:onion523/my-money@${commit} 的 web/src/components/utils.ts(EXPENSE_LEXICON、INCOME_LEXICON)。
// 規則的順序就是優先順序:第一個有任何關鍵字出現在備註裡的規則勝出,所以順序與特殊寫法都照上游,不自行「修正」。

/// 「智慧推薦」第二層:生活語意關鍵字詞庫(上游 ADR-0009)。
enum CategoryLexicon {
    struct Rule: Sendable {
        let category: String
        /// 已轉成小寫;比對時備註也轉成小寫。
        let keywords: [String]
    }

    static let expense: [Rule] = [
${swiftRules(expense)}    ]

    static let income: [Rule] = [
${swiftRules(income)}    ]
}
`)

// 對照表:每個關鍵字單獨一筆、大小寫變體、前後加字,以及規則兩兩組合(驗證規則的優先順序)。
const cases = new Set()
const add = (type, note) => cases.add(`${type}\t${note}`)
for (const [type, rules] of [['expense', expense], ['income', income]]) {
  for (const rule of rules) {
    for (const keyword of rule.keywords) {
      add(type, keyword)
      add(type, keyword.toUpperCase())
      add(type, `今天${keyword}費用`)
      add(type, `  ${keyword}  `)
    }
  }
  const firsts = rules.map((rule) => rule.keywords[0])
  for (const a of firsts) for (const b of firsts) if (a !== b) add(type, `${a}${b}`)
  // 同一個備註放兩種類型,確認類型不同結果不同。
  for (const note of firsts) add(type === 'expense' ? 'income' : 'expense', note)
}
for (const note of ['', '   ', 'zzz', '隨便寫寫', '123', 'Netflix 月費', 'netflix', '早餐', '下午茶', '中油加油站', '全聯買菜', '育兒津貼', '壓歲錢', '薪水入帳']) {
  add('expense', note)
  add('income', note)
}
const lines = [...cases].map((entry) => {
  const [type, note] = entry.split('\t')
  const result = upstream.recommendCategory(note, type)
  return `${type}\t${note}\t${result ? result.category : ''}`
})
writeFileSync(join(root, 'tests/MyMoneyDomainTests/CategoryLexiconGolden.swift'), `// 由 scripts/sync-category-lexicon.mjs 產生,不要手改。
// 來源:onion523/my-money@${commit} 的 recommendCategory(沒有歷史時,也就是只走詞庫層)在這些備註上的結果。
// 每行是「類型<Tab>備註<Tab>推薦的分類」,分類是空的代表上游沒有推薦。

enum CategoryLexiconGolden {
    static let table = """
${lines.join('\n')}
"""
}
`)
console.log(`支出 ${expense.length} 條規則、收入 ${income.length} 條規則,對照表 ${lines.length} 筆`)
