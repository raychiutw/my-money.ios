# DESIGN.md

my-money.ios 的 UI 與 UX 規範。依據是 Apple HIG(研究見 `docs/research/2026-09-28-apple-hig-ios-app.md`)和 ADR-0001 的規則「功能層與 web 對等，互動層照 HIG 轉譯」。品牌只保留 **logo** 和 **accent 色**,其餘一律使用系統外觀。

## 原則

- **系統外觀優先**:背景、surface、文字、分隔線全部用系統語意色(`systemGroupedBackground`、`secondarySystemGroupedBackground`、`label`、`secondaryLabel`……),字型只用系統 text style。
- **Liquid Glass 只出現在導覽層和控制層**,也就是 tab bar、toolbar、sheet 這些標準元件自帶的玻璃效果。內容層(帳戶卡、交易列、預算、圖表)不使用玻璃，也不自己刻玻璃效果。
- **不提供 app 內的外觀設定**,一律跟隨系統的淺色／深色(HIG Dark Mode:「Avoid offering an app-specific appearance setting」)。增強對比、減少透明度、減少動態效果都要能正常呈現。
- **不用 emoji 當介面圖示**,改用 SF Symbols。儲蓄目標的 emoji 是使用者資料，照原樣顯示。
- 所有 UI 文字使用 `CONTEXT.md` 的詞彙。

## 顏色

`AccentColor` 放在 asset catalog,提供四個變體。

| 外觀 | 色碼 | 對比 |
|---|---|---|
| 淺色 | `#B8434D` | 對白色 5.3:1,對 `systemGroupedBackground` 4.8:1 |
| 深色 | `#FF8A8A`(品牌原色) | 對深色背景約 7.5:1 |
| 淺色 + 增強對比 | `#9E2F3A` | — |
| 深色 + 增強對比 | `#FFB3B3` | — |

- web 的品牌粉 `#FF8A8A` 對白底只有 2.27:1,不能直接當淺色模式的文字 tint。HIG 要求自訂顏色的對比至少 4.5:1。
- 語意色:
  - 收入用 `systemGreen`,支出用 `systemRed`。
  - 接近上限用 `systemOrange`,超支用 `systemRed`。
  - 目標達成用 `systemGreen`。
- **資訊不能只靠顏色傳達**:金額一律帶 `+` 或 `−` 號;公帳和私帳用 symbol 加文字標示。
- **帳戶顏色**是使用者選的資料，只用在帳戶列前緣的色塊，不當成唯一的辨識依據。

## 字型與數字

- 只用系統 text style,支援 Dynamic Type 到最大的無障礙字級。
- 金額加上 `.monospacedDigit()`。
- 新台幣的顯示跟 web 一致：例如 `$1,234` 和 `-$1,500`,0 位小數，捨入規則是 away from zero。

## 導覽(ADR-0003)

```text
Tab bar(iPad 用 .sidebarAdaptable)
  總覽   house
  交易   list.bullet.rectangle
  帳戶   creditcard
  統計   chart.bar            ← 含預算
  規劃   calendar             → 固定收支 / 儲蓄目標 / 現金流預測(列表 push)
總覽 toolbar 右上  person.crop.circle → 帳號 sheet(自帶 NavigationStack)
                   名稱與 email、家庭、機器人記帳、登出
總覽、交易 toolbar  plus → 「記一筆」sheet
```

- 視角(全部、家庭、個人)放在總覽、交易、統計頁頂端，用 segmented `Picker`。
- 登入和註冊是全螢幕流程，不放在 tab 裡。

## 元件對照(web → iOS)

| web | iOS |
|---|---|
| 自訂 Modal 表單 | `.sheet` 裡放 `NavigationStack` + `Form`,toolbar 放「取消」和「儲存」 |
| `window.confirm` 刪除確認 | `.confirmationDialog`,按鈕用 `role: .destructive` 並附「取消」。後端刪除無法復原，所以一律確認，不做 undo |
| `alert()` 顯示錯誤 | 表單裡的錯誤放在 `Section` footer;列表操作的錯誤用 `.alert` |
| 表單內的紅框錯誤 | 同上 |
| 主題切換鈕 | 移除，跟隨系統 |
| 下載 CSV | `ShareLink` 分享檔案 |
| `navigator.clipboard` 複製 | `UIPasteboard`,按鈕文字暫時改成「已複製」 |
| `<select>` | `Picker` |
| 公帳／私帳、支出／收入的切換鈕 | segmented `Picker` |
| `<input type=date>` | `DatePicker(.compact)` |
| `<input type=month>` | 月份 `Picker`(年、月) |
| 金額輸入 | `TextField` 綁定 `Decimal`,鍵盤用 `.numberPad`,鍵盤 toolbar 放「完成」鈕(number pad 沒有 Return 鍵) |
| 色點選擇器(帳戶顏色) | 8 色的圓形按鈕列，每個都有 accessibility label |
| emoji 選擇器(目標) | 12 個 emoji 的格狀按鈕 |
| 空狀態 | `ContentUnavailableView`,文字沿用 web |
| loading | `ProgressView`。資料回來之前不顯示 `$0` 或「安全」這類預設值 |
| Recharts 圓餅、柱狀、面積圖 | Swift Charts 的 `SectorMark`、`BarMark`、`AreaMark` |
| ProgressBar | `ProgressView(value:)` 或 `Gauge`,顏色依語意色 |

## 分類圖示

| 分類 | SF Symbol | 分類 | SF Symbol |
|---|---|---|---|
| 餐飲 | `fork.knife` | 薪資 | `banknote` |
| 交通 | `tram.fill` | 獎金 | `gift` |
| 娛樂 | `gamecontroller` | 投資 | `chart.line.uptrend.xyaxis` |
| 購物 | `bag` | 兼職 | `briefcase` |
| 生活 | `lightbulb` | 其他 | `shippingbox` |
| 醫療 | `cross.case` | 不在清單中的分類 | `tag` |
| 教育 | `book` | | |

機器人記帳可能寫入不在清單中的分類(例如「副業」),所以需要 fallback 圖示。

## 無障礙

- 觸控目標至少 44×44 pt。
- 金額的 VoiceOver 念法要帶出收支方向，例如「支出 120 元」。
- 圖表的每個元素都要有 accessibility label,另外保留 Swift Charts 預設的 Audio Graph。
- 支援減少動態效果：不做裝飾性的動畫。

## App icon

- 以 lucide `BookHeart`(ISC 授權)加品牌粉為基礎，用 Icon Composer 做成 Liquid Glass 分層 icon。素材、設計說明和授權聲明在 `design/app-icon/`。
- 深色外觀另外指定顏色：書用 `#FF8A8A`,愛心用 `#FFB3B3`。clear 和 tinted 變體由系統自動產生。
- SF Symbols 的授權不允許用在 app icon。
