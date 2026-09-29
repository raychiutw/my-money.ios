# DESIGN.md

my-money.ios 的 UI 與 UX 規範。依據是 Apple HIG(研究見 `docs/research/2026-09-28-apple-hig-ios-app.md`)和 ADR-0001 的規則「功能層與 web 對等，互動層照 HIG 轉譯」。品牌只保留 **logo** 和 **accent 色**,其餘一律使用系統外觀。

## 原則

- **系統外觀優先**:背景、surface、文字、分隔線全部用系統語意色(`systemGroupedBackground`、`secondarySystemGroupedBackground`、`label`、`secondaryLabel`……),字型只用系統 text style。
- **Liquid Glass 只出現在導覽層和控制層**,也就是 tab bar、toolbar、sheet 這些標準元件自帶的玻璃效果。內容層(帳戶卡、交易列、預算、圖表)不使用玻璃，也不自己刻玻璃效果。
- **外觀三選一，預設跟隨系統**:帳號 sheet 的「外觀」選擇列可選跟隨系統、淺色、深色。沒動過設定時跟隨系統的淺色／深色，包括系統依時間自動切換。
  - 選擇只記在這台裝置(composition root 注入的 UserDefaults),不送後端。
  - 由 composition root 設在 window 的 `overrideUserInterfaceStyle`,登入頁、所有 sheet 和 alert 立即一起變。不用 `preferredColorScheme`:帳號 sheet 開著時切到深色，之後再切成淺色或跟隨系統，sheet 都停在深色(#62 的截圖驗證)。
  - 啟動畫面由系統顯示，照系統外觀，不受這個設定影響。
  - **跟 HIG 的出入**:HIG Dark Mode 建議「Avoid offering an app-specific appearance setting」。理由：家人明確要求在 app 裡固定淺色或深色，web 也有主題切換鈕(parity 刻意偏離第 16 項)。預設維持跟隨系統，沒動過設定的人不受影響。
- 增強對比、減少透明度、減少動態效果都要能正常呈現。強制淺色或深色時，增強對比照樣生效，`AccentColor` 的四個變體照常套用。
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
- **資訊不能只靠顏色傳達**:金額一律帶 `+` 或 `−` 號;家庭公帳和個人私帳用 symbol 加文字標示。
- **帳戶顏色**是使用者選的資料，只用在帳戶列前緣的色塊，不當成唯一的辨識依據。

## 字型與數字

- 只用系統 text style,支援 Dynamic Type 到最大的無障礙字級。
- **輔助文字最小用 `subheadline`**(#43:家人反映字太小)。說明、次要資訊用 `subheadline`,
  更次要的註記才用 `footnote`;`caption` 只留給聊天泡泡下的時間這類附屬標記，不用 `caption2`。
  `body` 以上的字級不動。
- 分段控制的字也是 `subheadline`(預設是 13pt,在 composition root 用 appearance 設定);
  記一筆最上面的「帳本分類」和「支出／收入」再用 `.controlSize(.large)` 加高。
- 金額加上 `.monospacedDigit()`。
- 新台幣的顯示跟 web 一致：例如 `$1,234` 和 `-$1,500`,0 位小數，捨入規則是 away from zero。

## 說明文字

依 HIG Writing:「Check each word to be sure it needs to be there. If you can use fewer words, do so.」,以及「small screens require brevity」。畫面上只留下面 7 類文字，其餘解釋名詞、計算方式、功能用途的說明文字和宣傳句一律不寫，也不做資訊按鈕(ⓘ)把說明收起來再點開(#60)。

1. 確認對話框的訊息。
2. 警告：一句話說明會造成不可逆或意外的後果。例如預算額度設定後無法刪除、模擬對話會寫入真的交易記錄、預測餘額會跌破 0、有 N 個分類超支。
3. 錯誤，以及操作不能進行的原因。例如收款成員沒有可收款帳戶。
4. 空狀態：只留標題和「下一步」(例如總覽的「至帳戶管理新增…」),不寫宣傳句。
5. 資料：
   - 含數字或日期的明細，例如收入 x · 支出 y、已出帳待繳款與未出帳款、N 個現金錢包、整體達成率、最低餘額發生日、邀請碼有效期限、欠款公私拆解。
   - 功能產出的結果，例如購買力試算的評估說明、分攤建議。
   - 聊天內容。
6. 完成流程必要的指示：機器人的「傳送：綁定 驗證碼」。
7. 登入、註冊頁的標語和「還沒有帳號？」這類連結前導。

- 需要讓人知道「不能操作」的地方，用 symbol 加 accessibility label,不另外寫說明。例如系統分類交易記錄的鎖定標記(見「分類圖示」)。
- 刪掉 footer 之後，空的 `Section` 一併整理，不留空白。
- 跟 web 的差異見 parity 刻意偏離第 43 項。

## 導覽(ADR-0003)

```text
Tab bar(iPad 用 .sidebarAdaptable)
  總覽   house
  交易   list.bullet.rectangle
  帳戶   creditcard
  統計   chart.bar            ← 含預算
  規劃   calendar             → 週期收支 / 儲蓄目標 / 現金流預測(列表 push)
總覽 toolbar 右上  person.crop.circle → 帳號 sheet(自帶 NavigationStack)
                   名稱與 email、家庭、機器人記帳、外觀、登出
總覽、交易 toolbar  plus → 「記一筆」sheet
總覽、統計 toolbar  line.3.horizontal.decrease → 視角選單(全部、家庭、個人)
帳戶 toolbar        line.3.horizontal.decrease → 帳戶檢視範圍選單(全部、家庭共同基金、個人私帳)
                    arrow.left.arrow.right → 「ATM 提款／轉帳」sheet;plus → 新增資產帳戶選單
```

- **視角**(全部、家庭、個人):總覽、統計頁放在 toolbar 的篩選按鈕(`line.3.horizontal.decrease`),點開是可勾選的選單(`ScopeFilter.swift`);導覽列副標題(`navigationSubtitle`)一律顯示目前的視角，不用打開選單就知道現在看的範圍。清單最上面不放分段控制，打開畫面最上面就是資料。
  - VoiceOver:篩選按鈕的標籤是「視角」,值是目前的選擇。
  - HIG 依據:pull-down button 適合三個以上的選項;toolbar 的項目要精選，加上篩選按鈕之後，每頁的 toolbar 不超過三組。
  - 交易頁的視角暫時還在清單最上面(segmented `Picker`),#74 會跟日期區間、類型、分類一起收進篩選 sheet。
- **帳戶檢視範圍**(全部、家庭共同基金、個人私帳):帳戶頁放在 toolbar 的篩選按鈕，跟視角共用同一個元件(`ScopeFilter.swift`),點開是可勾選的選單;導覽列副標題一律顯示目前的範圍。清單最上面不放分段控制，依序是統計卡、現金錢包、銀行存款帳戶、信用卡四個 `Section`,每區有自己的空狀態(標題加新增按鈕)。
  - VoiceOver:篩選按鈕的標籤是「帳戶檢視範圍」,值是目前的選擇。
  - toolbar 是篩選、ATM 提款／轉帳、新增資產帳戶三組。
- 「ATM 提款／轉帳」是 sheet:入口在帳戶頁 toolbar(`arrow.left.arrow.right`),以及現金錢包列、銀行存款帳戶列的 leading swipe action(預選轉入或轉出)。撥款報銷也是 sheet,從家庭頁的代墊摘要打開。
- 信用卡的三個還款入口(繳家庭代墊、繳個人私帳、全額結清)是 borderless 按鈕，跟 web 一樣排成一排、只放文字;大字級放不下時改成帶 icon 的直排(`ViewThatFits`)。
- 登入和註冊是全螢幕流程，不放在 tab 裡。

## 元件對照(web → iOS)

| web | iOS |
|---|---|
| 自訂 Modal 表單 | `.sheet` 裡放 `NavigationStack` + `Form`,toolbar 放「取消」和「儲存」 |
| `window.confirm` 刪除確認 | `.confirmationDialog`,按鈕用 `role: .destructive` 並附「取消」。後端刪除無法復原，所以一律確認，不做 undo |
| `alert()` 顯示錯誤 | 表單裡的錯誤放在 `Section` footer;列表操作的錯誤用 `.alert` |
| 表單內的紅框錯誤 | 同上 |
| 主題切換鈕(淺色／深色兩段式) | 帳號 sheet 的「外觀」選擇列：跟隨系統、淺色、深色，預設跟隨系統(見「原則」) |
| 下載 CSV | `ShareLink` 分享檔案 |
| `navigator.clipboard` 複製 | `UIPasteboard`,按鈕文字暫時改成「已複製」 |
| `<select>` | `Picker` |
| 家庭公帳／個人私帳、支出／收入的切換鈕 | segmented `Picker` |
| `<input type=date>` | `DatePicker(.compact)` |
| `<input type=month>` | 月份 `Picker`(年、月) |
| 金額輸入 | 共用的 `AmountField`:靠右對齊、`.numberPad`、等寬數字，取得焦點時全選(直接輸入就取代原值)。綁定文字，儲存時用 `Money(wholeNumber:)` 解析;鍵盤 toolbar 放「完成」鈕(number pad 沒有 Return 鍵),按下清掉整個表單的焦點：表單的所有文字欄位(包括備註)綁到同一個 focus 狀態，不管焦點在哪個欄位都收起鍵盤;捲動表單也會收起鍵盤(`keyboardDismissal(clearing:)`) |
| 色點選擇器(帳戶顏色) | 8 色的圓形按鈕列，每個都有 accessibility label |
| emoji 選擇器(目標) | 12 個 emoji 的格狀按鈕 |
| 空狀態 | 整頁用 `ContentUnavailableView`;List 區塊裡用標題(`headline`)、下一步(`subheadline`,例如「至帳戶管理新增…」)加 borderless 按鈕。標題和下一步沿用 web,宣傳句不寫(見「說明文字」) |
| loading(web 的骨架屏) | 首次載入顯示骨架屏：跟載入後一樣的版面，放畫面自帶的固定佔位內容，套系統的 `.redacted(reason: .placeholder)`(`LoadingSkeleton.swift`)。VoiceOver 只念一次「載入中」,佔位不能點;資料回來時淡入 0.25 秒，開啟「減少動態效果」時不做動畫;不做微光(shimmer)。下拉更新、切換篩選時保留目前的內容，不回到骨架屏。資料回來之前不顯示 `$0` 或「安全」這類預設值 |
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

機器人記帳可能寫入不在清單中的分類(例如舊版寫入的「副業」),所以需要 fallback 圖示。

系統專用的分類「信用卡還款」(信用卡扣款還款產生的交易記錄)用 `creditcard.and.123`。這類交易記錄不能編輯或刪除，列表上只在列尾放鎖定標記 `lock.fill`,不放說明文字;VoiceOver 接在交易記錄後面念「系統紀錄，不能編輯或刪除」。家庭共同基金的標記用 `house.fill` 加上文字「家庭共同基金」。

## 無障礙

- 觸控目標至少 44×44 pt。
- 金額的 VoiceOver 念法要帶出收支方向，例如「支出 120 元」。
- 圖表的每個元素都要有 accessibility label,另外保留 Swift Charts 預設的 Audio Graph。
- 支援減少動態效果：不做裝飾性的動畫。

## App icon

- 以 lucide `BookHeart`(ISC 授權)加品牌粉為基礎，用 Icon Composer 做成 Liquid Glass 分層 icon。素材、設計說明和授權聲明在 `design/app-icon/`。
- 深色外觀另外指定顏色：書用 `#FF8A8A`,愛心用 `#FFB3B3`。clear 和 tinted 變體由系統自動產生。
- SF Symbols 的授權不允許用在 app icon。
