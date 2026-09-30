---
status: superseded by ADR-0004
---

# 帳號走 sheet,家庭與機器人記帳不占 tab

web 有 9 個頁面，手機版用 4 個 tab 加上一個「更多」抽屜。iOS 的 tab bar 只放 5 個頂層區域：總覽、交易、帳戶、統計、規劃。「規劃」底下是固定收支、儲蓄目標、現金流預測的列表。**家庭、機器人記帳和登出**則從總覽 toolbar 的帳號按鈕打開一個 sheet,sheet 裡有自己的 navigation stack。iPad 用 `.sidebarAdaptable`,入口跟 iPhone 是同一套。

HIG 規定 tab bar 只負責導覽，不應出現「更多」溢位，也不能把動作做成 tab。iPhone 超過 5 個 tab 時，系統會自動產生「更多」。家庭和機器人記帳屬於低頻的設定類操作，跟「現在在看哪筆帳」無關，放在帳號 sheet 符合 iOS 的慣例。「記一筆」是動作，所以放在 toolbar 的 + 按鈕。這個決定和 `trip-planner.flutter` 的 ADR-0010 相同。

## Considered Options

- **照 web,4 個 tab 加一個「更多」tab**:這正是 HIG 明確不建議的溢位做法。
- **依裝置分開**(iPad 的 sidebar 攤開全部 9 頁，iPhone 用 `defaultVisibility(.hidden, for: .tabBar)` 只顯示 5 個):iPad 比較好找，但要維護和驗收兩套導覽。
