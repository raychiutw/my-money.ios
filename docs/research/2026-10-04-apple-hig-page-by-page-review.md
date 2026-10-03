# Apple HIG 逐頁審查（iPhone）

查核日期：2026-10-04（Asia/Taipei）

對應票：#157。後續票：#161～#167。

## 範圍與方法

- **範圍**：截圖巡覽（`scripts/screen-tour.sh`）拍的 28 頁，每頁對照 Apple Human Interface Guidelines。只審 iPhone 17（iOS 27 模擬器）；iPad 另開 #166。
- **拍攝組合**：淺色 × 預設／XXL／AX5 字級，以及深色 × 預設字級。深色的 XXL 與 AX5 沒有巡覽（執行中磁碟寫滿，巡覽被中斷），不在這次審查內。AX5 的「現金流預測」頁巡覽沒走到（#167），改由 UI 測試在 XXL 驗證。
- **看過的範圍**：淺色預設字級逐頁看過全部 28 頁；XXL 與 AX5 看過總覽、交易、帳戶、家庭、記一筆、各編輯表單、規劃相關頁與機器人；深色預設看過登入、總覽、記一筆、「我的」、交易、帳戶、家庭、統計、預測、儲蓄目標、週期收支、信用卡詳細頁、機器人對話、預算額度、儲蓄目標編輯與轉帳。下面每一列只寫實際看到的。
- **HIG 原文**：HIG 網頁由 JavaScript 渲染，一律抓官方 DocC JSON（`https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<頁>.json`）讀全文。引用的原文都是從那裡取的。
- **缺失的處理**：小而且能先寫失敗測試的，在本 PR 修正（測試真的跑到紅燈，也用舊程式確認會失敗）；需要設計決定或要先實驗的，開票。

結論符號：

- ✅ 符合
- ⚠️ 刻意偏離或有取捨（理由寫在該列，或已記在 ADR／DESIGN.md）
- ❌ 缺失（一定有「已修正」或票號）
- 📱 要真機才判斷得準

## 依據的 HIG 章節

- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)：「Keep text truncation to a minimum as font size increases」，大字級放不下時改成上下排的版面，不是截斷或擠壓。
- [Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields)：placeholder 在開始輸入時就消失，所以要另外放一個標籤說明欄位用途。
- [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)：列的文字要精簡，減少截斷與換行。
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)、[Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)、[Menus](https://developer.apple.com/design/human-interface-guidelines/menus)
- [Charts](https://developer.apple.com/design/human-interface-guidelines/charts)、[Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)、[Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers)、[Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)、[Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Managing accounts and sign-in](https://developer.apple.com/design/human-interface-guidelines/managing-accounts-and-sign-in)、[Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data)

專案自己的決定：ADR-0007（按鈕有玻璃外框、沒有裸文字按鈕）、ADR-0008（按鈕不填色、選取用品牌粉紅）、DESIGN.md「列與欄位」。前一輪的版面研究見 [2026-09-29-apple-hig-layout-review.md](2026-09-29-apple-hig-layout-review.md)。

## 缺失總表

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 「我的」sheet 的 ✕ 被系統填成黑色（深色是白色） | ❌ | ADR-0008 | 已修正：改放 `.primaryAction`（`.confirmationAction` 會被自動填色） |
| 家庭頁「誰轉給誰」那行字被長條圖標註壓住（預設、XXL、AX5 都有） | ❌ | Typography：大字級不重疊 | 已修正：圖上方留一個標註高度，隨字級放大 |
| 備註欄只有 placeholder，打字後看不出是什麼欄位（記一筆、轉帳、信用卡還款、報銷） | ❌ | Text fields；DESIGN.md「列與欄位」第 8 條 | 已修正：`LabeledContent("備註")` |
| 登入與註冊的欄位只有 placeholder | ❌ | Text fields；Managing accounts and sign-in | 已修正：每欄有標籤 |
| 加標籤後，大字級下標籤在欄位上方，點標籤不會開始輸入 | ❌ | Accessibility | 已修正：整列點了就對焦（`tapToFocus`） |
| 總覽目標圓環的「100%」在預設字級被截成「10…」 | ❌ | Typography | 已修正：圓環放大、內距縮小 |
| 總覽「最近」交易列在 AX5 名稱被擠成一字一行 | ❌ | Typography：改上下排 | 已修正：無障礙字級上下排，金額靠右在最下面 |
| 預測圖日期刻度在 XXL 被截成「10月1…」 | ❌ | Typography；Charts | 已修正：大字級少放刻度 |
| 預算額度編輯的金額列標籤在 XXL 被截成「2026年10月的…」 | ❌ | Typography | 已修正：月份放區塊標題，標籤只剩「預算」 |
| 預測頁文案「0,請及早調整」用了半形逗號 | ❌ | 繁體中文標點 | 已修正：改全形，並加文案規則測試掃描 `src/` |
| 機器人對話的送出鈕是裸圖示 | ❌ | ADR-0007 | 已修正：玻璃圓鈕 |
| 機器人對話的輸入欄在 AX5 不跟著放大 | ❌ | Typography | 已修正：改用會縮放的樣式 |
| AX5 下日期選擇器比卡片寬、被切掉（記一筆、轉帳、信用卡還款、報銷、儲蓄目標、交易篩選） | ❌ | Typography；Pickers | #161 |
| AX5 下總覽帳戶卡的名稱被截成「iOS 測試…」 | ❌ | Typography | #162 |
| AX5 下交易頁長條圖的金額標註壓到「支出佔收入」進度條 | ❌ | Typography | #163 |
| 統計頁月份切換是裸 chevron，跟交易頁的玻璃膠囊不一致 | ❌ | ADR-0007 | #164（要先決定） |
| 篩選 sheet 的「重設為本月」是純文字列，看不出可以按 | ❌ | ADR-0007／0008 | #165（要先決定） |
| 巡覽在 AX5 找不到「現金流預測」入口而中斷 | ❌ | 開發工具 | #167 |

## 逐頁審查

### `login`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 電子郵件、密碼欄只有 placeholder | ❌ | Text fields | 已修正：加標籤，placeholder 只放範例 |
| 登入鈕是玻璃膠囊，欄位沒填完時停用 | ✅ | ADR-0007 | — |
| 「還沒有帳號？立即註冊」是帶箭頭的文字連結 | ⚠️ | 次要導覽連結，不是動作按鈕 | 維持現狀；要改成玻璃膠囊請另提 |
| 顯示／隱藏密碼的眼睛是欄位內的附屬圖示，觸控範圍 44pt | ⚠️ | 同 Apple 登入欄的做法 | 維持 |
| AX5：標題與副標折行、欄位上下排 | ✅ | Typography | — |
| 淺色與深色對比 | ✅ | Dark Mode | — |

### `register`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 姓名、電子郵件、密碼、確認密碼只有 placeholder，第一個密碼欄只寫「至少 6 個字元」 | ❌ | Text fields | 已修正：四欄都有標籤，提示留在 placeholder |
| 返回是玻璃圓鈕，標題置中 | ✅ | Toolbars | — |
| 「已有帳號？登入」文字連結 | ⚠️ | 同 `login` | 維持現狀 |

### `overview`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 工具列：篩選與「＋」在同一個玻璃群組，頭像獨立 | ✅ | Toolbars | — |
| 沒有導覽大標題，由「淨可用餘額」主視覺取代 | ⚠️ | 首頁對齊設計稿（#124） | 維持 |
| 目標圓環「100%」預設字級被截成「10…」 | ❌ | Typography | 已修正 |
| AX5：「最近」交易列名稱一字一行 | ❌ | Typography | 已修正 |
| AX5：帳戶卡名稱被截成「iOS 測試…」 | ❌ | Typography | #162 |
| 區塊標題右邊的「…」選單，觸控範圍 44pt | ✅ | Menus | — |
| 超支提示以紅色加圖示加文字表示，不只靠顏色 | ✅ | Color；Accessibility | — |
| 頭像的字與底色對比（深色） | 📱 | Color | 模擬器量不準，等真機深色確認（0.4.0 起的待辦） |
| 淺色與深色 | ✅ | Dark Mode | — |

### `quick-entry`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| ✕ 與 ✓ 是同樣的玻璃圓鈕、不填色 | ✅ | ADR-0008 | — |
| 備註欄只有 placeholder | ❌ | Text fields | 已修正 |
| 歸屬是內嵌選擇列，選取的勾勾是品牌粉紅 | ✅ | ADR-0008 | — |
| 數字鍵盤上方的「完成」膠囊（number pad 沒有 Return） | ✅ | Entering data | — |
| XXL：鍵盤上方的「完成」膠囊貼著金額列 | ⚠️ | 系統鍵盤工具列浮在內容上，無法控制位置 | 維持 |
| AX5：日期列被切掉 | ❌ | Typography | #161 |
| 淺色與深色 | ✅ | Dark Mode | — |

### `quick-entry-account`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 帳戶選擇推入清單頁，有系統的返回鈕與標題 | ✅ | Lists and tables | — |
| 每列是名稱加「帳戶類型・歸屬」兩行 | ✅ | Lists and tables | — |

### `quick-entry-recommended`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 輸入備註時，注音鍵盤與表單並存，備註欄不被鍵盤擋住 | ✅ | Entering data | — |
| 依備註預選分類的提示放在備註欄正下方 | ✅ | DESIGN.md（#99） | — |

### `me-settings`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 右上的 ✕ 被填成黑色（深色是白色） | ❌ | ADR-0008 | 已修正 |
| 「設定｜規劃」分段控制；AX 字級換成選單 | ✅ | Segmented controls | — |
| 外觀選擇是內嵌選擇列，勾勾是品牌粉紅 | ✅ | ADR-0008 | — |
| 「登出」是紅字列 | ✅ | 破壞性動作用紅色；登出不刪資料，不需確認 | — |
| 增強對比下的品牌粉紅與玻璃外框對比 | 📱 | Color | 等真機確認 |

### `bot`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 「產生綁定驗證碼」是一列純文字，看不出可以按 | ⚠️ | 與 `transaction-filter` 的「重設為本月」同類 | 等 #165 決定後一併套用 |
| 複製網址的圖示是列內的附屬圖示，沒有外框 | ⚠️ | 同欄位內附屬圖示的做法 | 維持 |
| 長網址從中間截斷（`…`） | ✅ | Lists and tables：中間截斷保留頭尾 | — |

### `bot-chat`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 送出鈕是裸圖示 | ❌ | ADR-0007 | 已修正 |
| 輸入欄在 AX5 不跟著放大 | ❌ | Typography | 已修正 |
| 頂端橘色警示橫幅說明「會寫入真的交易記錄」 | ✅ | Feedback | — |
| 範例晶片橫向捲動，邊緣露出一半提示可捲 | ✅ | Layout | — |

### `transactions`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 搜尋欄是系統的 `.searchable`；AX5 字級由系統決定 | ✅ | Search fields | — |
| 月份切換是玻璃膠囊，中間點開選任意年月 | ✅ | DESIGN.md（#130） | — |
| AX5：長條圖的金額標註壓到進度條 | ❌ | Typography | #163 |
| 交易列：金額靠右，AX 字級金額在最下面靠右 | ✅ | 設計稿 | — |
| 淺色與深色 | ✅ | Dark Mode | — |

### `transaction-filter`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 中／大兩種高度、有 grabber | ✅ | Sheets | — |
| 視角是分段控制 | ✅ | Segmented controls | — |
| 「重設為本月」是純文字列 | ❌ | ADR-0007／0008 | #165 |
| AX5：起日與迄日的日期選擇器被切掉 | ❌ | Typography | #161 |

### `accounts`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 「ATM 提款／轉帳」與「立即建立現金錢包」是玻璃膠囊 | ✅ | ADR-0007 | — |
| 資產與負債比例條有文字圖例與數字磚，不只靠顏色 | ✅ | Color | — |
| 空區塊有說明與下一步 | ✅ | Feedback | — |
| AX5：數字磚改單欄 | ✅ | Typography | — |

### `account-editor-cash`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 類型、歸屬是內嵌選擇列 | ✅ | ADR-0004 | — |
| 代表色色塊橫向捲動，選取的有勾勾，不只靠顏色 | ✅ | Color；Accessibility | — |
| 預設選取的色塊在畫面外時，第一眼看不到哪個被選 | ⚠️ | 橫向捲動的取捨 | 維持 |
| 欄位都有標籤 | ✅ | Text fields | — |

### `account-editor-bank`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 與現金錢包同樣的版型，欄位標籤是「餘額」 | ✅ | Text fields | — |

### `account-editor-card`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 信用額度、結帳日、繳款日各有標籤，日期推入清單頁 | ✅ | Pickers | — |
| 數字欄靠右、等寬數字 | ✅ | Typography | — |

### `transfer`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 備註欄沒有標籤 | ❌ | Text fields | 已修正 |
| 轉出、轉入帳戶推入選擇 | ✅ | Lists and tables | — |
| AX5：日期被切掉 | ❌ | Typography | #161 |

### `card-detail`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 導覽列右邊的「編輯」是帶玻璃外框的文字鈕 | ⚠️ | HIG 的 Toolbars 允許文字鈕；有外框符合 ADR-0007 | 維持 |
| 「繳款」是選單，項目含全額結清與自訂 | ✅ | Menus | — |
| 每區塊是標籤加金額一列，AX5 上下排 | ✅ | Lists and tables | — |

### `card-payment`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 備註欄沒有標籤 | ❌ | Text fields | 已修正 |
| 歸屬是內嵌選擇列 | ✅ | ADR-0008 | — |
| AX5：日期被切掉 | ❌ | Typography | #161 |

### `household-joined`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 「誰轉給誰」那行字被長條圖標註壓住 | ❌ | Typography | 已修正 |
| 「查看代墊明細」「從共同基金報銷」是圖示加文字的列 | ⚠️ | 與 `bot` 同類；有圖示可辨識為動作 | 維持 |
| 「離開家庭」是紅字列，點了有確認 | ✅ | Alerts | — |
| 報銷表單（從這頁進入，巡覽沒有拍）的備註欄沒有標籤 | ❌ | Text fields | 已修正 |
| 長條圖有 accessibility label，每根念「成員，公帳代墊 N 元」 | ✅ | Charts | — |

### `household`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 建立家庭、用邀請碼加入，欄位都有標籤（名稱、邀請碼） | ✅ | Text fields | — |
| 「建立」「加入」是玻璃膠囊，欄位沒填時停用 | ✅ | ADR-0007 | — |

### `statistics`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 月份切換是裸 chevron，沒有玻璃外框 | ❌ | ADR-0007 | #164 |
| 圓餅圖與清單共用同一份顏色，清單有名稱與金額 | ✅ | Charts：顏色不是唯一資訊 | — |
| 超出調色盤的分類都是灰色 | ⚠️ | 清單有名稱，不影響辨識 | 維持 |
| 預算超支以紅色加圖示加「超支 $20」文字表示 | ✅ | Color | — |
| 趨勢圖有圖例，收入綠、支出紅 | ✅ | Charts | — |

### `budget-editor`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 金額列標籤「2026年10月的預算」在 XXL 被截斷 | ❌ | Typography | 已修正 |
| 分類格在金額下面，sheet 半高也填得到金額 | ✅ | DESIGN.md（#101） | — |
| 「設定後無法刪除。」只留警告，不寫操作說明 | ✅ | DESIGN.md「說明文字」 | — |

### `me-planning`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 三個入口是圖示加文字加 chevron 的列 | ✅ | Lists and tables | — |
| 「我的」的 ✕ 填色 | ❌ | ADR-0008 | 已修正（同 `me-settings`） |

### `recurring`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 工具列三顆（篩選、＋、…）在同一個玻璃群組，副標顯示視角 | ✅ | Toolbars | — |
| 每列：名稱、金額、週期與日、記帳人與歸屬、帳戶 | ✅ | 設計稿 | — |
| AX5：金額在最下面靠右 | ✅ | Typography | — |

### `recurring-editor`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 欄位都有標籤 | ✅ | Text fields | — |
| 週期、歸屬是內嵌選擇列，扣款日推入清單頁 | ✅ | ADR-0004 | — |
| 週期支出／收入分段控制放在導覽列中間 | ✅ | Segmented controls | — |
| XXL：名稱欄上下排 | ✅ | Typography | — |

### `goals`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 「＋ 存入」是玻璃膠囊 | ✅ | ADR-0007 | — |
| 已達成以綠色勾加「已達成目標」文字表示 | ✅ | Color | — |
| 進度條旁沒有百分比，數字在 VoiceOver 念 | ✅ | DESIGN.md（#77） | — |

### `goal-editor`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 圖示格選取有外框，不只靠顏色 | ✅ | Color | — |
| 欄位有標籤，「截止日」用 Toggle | ✅ | Toggles | — |
| 截止日打開後的日期選擇器在 AX5 被切掉 | ❌ | Typography | #161 |

### `forecast`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 「預計餘額會跌破 0,請…」半形逗號 | ❌ | 繁體中文標點 | 已修正 |
| XXL：日期刻度被截成「10月1…」 | ❌ | Typography；Charts | 已修正 |
| 透支風險以紅色加圖示加文字表示 | ✅ | Color | — |
| 圖表每個資料點有 accessibility label | ✅ | Charts | — |
| 視角篩選在導覽列右邊，副標顯示目前視角 | ✅ | Toolbars | — |

## 通則（每頁都檢查過）

- 工具列與 sheet 的按鈕：✕、✓、返回、篩選、＋、…一律是不填色的玻璃按鈕；沒有裸文字按鈕，需要文字的主要動作是玻璃膠囊。
- 導覽列的標題與內文的 Dynamic Type：內文隨字級放大，導覽列的標題由系統限制大小（HIG 的系統行為）。
- 金額一律單行、靠右、等寬數字。
- 顏色不是唯一資訊：超支、透支、已達成、選取都有圖示或文字。
- 深色模式：卡片、文字、圖表在預設字級下沒有看到對比問題。

## 尚未涵蓋

- iPad：#166。
- 深色的 XXL 與 AX5：巡覽被磁碟寫滿中斷；下一輪巡覽補。
- 真機：玻璃按鈕外框的對比、增強對比下的品牌粉紅、深色頭像（📱）。
- 巡覽沒有拍到的 sheet：報銷表單（已修正備註欄，沒有逐項審）、離開家庭的確認。
