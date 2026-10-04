# Apple HIG 逐頁審查（iPad）

查核日期：2026-10-04（Asia/Taipei）

對應票：#166。後續票：#173、#174，另外 #169 的 iPad 證據。iPhone 的審查見 [2026-10-04-apple-hig-page-by-page-review.md](2026-10-04-apple-hig-page-by-page-review.md)。

## 範圍與方法

- **裝置**：iPad Air 11 吋（M4）、iPadOS 27 模擬器，直向。截圖巡覽（`scripts/screen-tour.sh -t "iPad Air 11-inch (M4)"`）拍淺色與深色的預設字級，各 51 張、每頁都有。
- **依你的決定**：只審查加開票，**這份不修任何程式**；缺失一律開票。
- **HIG 依據**：[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)、[Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)、[Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)、[Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)、[Pointing devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices)。大字級、深色、按鈕與欄位的規則同 iPhone 那份，沒有重審。
- **看過的**：每一頁的淺色預設字級；深色預設看過總覽、記一筆、離開家庭確認，其餘頁跟淺色同一份程式，只有顏色不同。
- **結論符號**：同 iPhone 那份——✅ 符合；⚠️ 刻意偏離或有取捨；❌ 缺失（一定有票號）；📱 要真機。

## iPad 通則

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| tab 在畫面上方（`.sidebarAdaptable`），最左邊有側邊欄開關，右邊是視角、記一筆、頭像 | ✅ | Tab bars | — |
| sheet 是置中的 form sheet，寬約 480pt，高度依內容、可往上拉 | ✅ | Sheets | — |
| 各 tab 的內容撐滿整個 820pt 寬，沒有限制可讀寬度 | ❌ | Layout：iPad 的內容要限制寬度 | #173 |
| 沒有鍵盤快速鍵、沒有指標懸停效果 | ⚠️ | Keyboards；Pointing devices | #174（要你決定） |
| 數字鍵盤在 iPad 是完整的標點鍵盤（系統沒有 iPad 的 number pad），鍵盤上方的「完成」膠囊浮在 sheet 外面 | ⚠️ | 系統行為 | 維持 |
| 確認訊息的泡泡出現在畫面上方，箭頭沒有指著觸發它的按鈕 | ❌ | Action sheets | #169 |

## 逐頁審查

### `login`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 欄位與按鈕撐滿 800pt 寬，電子郵件欄的標籤與輸入離得很遠 | ❌ | Layout | #173 |
| 欄位標籤、登入鈕、註冊連結的內容跟 iPhone 一樣 | ✅ | Text fields | — |

### `register`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 四個欄位撐滿整個寬度 | ❌ | Layout | #173 |
| 返回鈕與標題 | ✅ | Toolbars | — |

### `overview`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 走勢圖、三格數字、帳戶卡兩欄；數字磚與卡片的欄數依寬度自適應 | ✅ | Layout | — |
| 「最近」的列左邊名稱、右邊金額隔了七百多 pt | ❌ | Layout | #173 |
| 目標環「100%」完整顯示 | ✅ | Typography | — |

### `quick-entry`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| form sheet 置中，✕ 與 ✓ 是玻璃圓鈕 | ✅ | Sheets | — |
| 數字鍵盤是完整標點鍵盤，「完成」浮在 sheet 外面 | ⚠️ | 系統行為 | 維持 |
| 分類格在鍵盤出現時被擋住一半，捲動可看到 | ✅ | Keyboards | — |

### `quick-entry-account`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 推入的帳戶清單，在 form sheet 裡有返回鈕與標題 | ✅ | Lists and tables | — |

### `quick-entry-recommended`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 注音鍵盤與備註欄並存，備註欄不被鍵盤擋住 | ✅ | Entering data | — |

### `me-settings`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 「我的」是置中的 form sheet，分段控制、外觀、登出都在視窗內 | ✅ | Sheets | — |

### `bot`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 在「我的」的 form sheet 裡推入，iPad 的寬度放得下完整網址，複製鈕在右邊 | ✅ | Lists and tables | — |

### `bot-chat`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 輸入欄與送出鈕在 form sheet 底部，快捷晶片在上方 | ✅ | Layout | — |

### `transactions`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 搜尋欄、月份膠囊、淨收支主視覺、長條圖都撐滿寬度；交易列名稱與金額隔很遠 | ❌ | Layout | #173 |
| 工具列：視角、記一筆、頭像 | ✅ | Toolbars | — |

### `transaction-filter`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| form sheet 中等高度、可往上拉；日期選擇器、內嵌選擇列都正常 | ✅ | Sheets | — |

### `accounts`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 比例條、數字磚與帳戶列撐滿寬度，帳戶列的名稱與金額隔很遠 | ❌ | Layout | #173 |

### `account-editor-cash`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 跟其他帳戶表單同一份程式（只有類型不同），在 form sheet 裡版面一致 | ✅ | Sheets | — |

### `account-editor-bank`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 同上 | ✅ | Sheets | — |

### `account-editor-card`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 信用卡欄位較多，form sheet 內可捲動、結帳日與繳款日推入清單頁 | ✅ | Sheets | — |

### `transfer`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 轉出、轉入、金額、日期、備註，form sheet 內版面緊湊 | ✅ | Sheets | — |

### `card-detail`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 推入頁撐滿寬度，標籤與金額隔很遠；返回鈕與「編輯」在導覽列 | ❌ | Layout | #173 |

### `card-payment`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| form sheet 內版面一致，備註有標籤 | ✅ | Text fields | — |

### `household-joined`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 長條圖撐得很寬，兩根長條各約 270pt；標註與「誰轉給誰」之間有空隙 | ❌ | Layout | #173 |
| 成員列名稱與待報銷金額隔很遠 | ❌ | Layout | #173 |

### `household`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 建立家庭、用邀請碼加入，欄位撐滿寬度 | ❌ | Layout | #173 |

### `statistics`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 圓餅圖固定大小、置中，分類清單撐滿寬度 | ❌ | Layout | #173 |
| 月份膠囊（共用的 `MonthPill`）置中 | ✅ | Layout | — |

### `budget-editor`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| form sheet 內分類格四欄變六欄（依寬度自適應），選取外框清楚 | ✅ | Layout | — |

### `me-planning`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 三個入口在 form sheet 裡只佔上方，下面大片空白 | ⚠️ | 規劃的三個入口預計搬到首頁（#171），這個畫面會消失 | 維持 |

### `recurring`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 在「我的」的 form sheet 裡推入，三顆工具列按鈕在同一個玻璃群組 | ✅ | Toolbars | — |

### `recurring-editor`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 週期、歸屬為內嵌選擇列，扣款日推入清單頁 | ✅ | Pickers | — |

### `goals`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 在 form sheet 裡推入，進度條、「存入」膠囊正常 | ✅ | Layout | — |

### `goal-editor`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 圖示格兩列六欄、選取外框清楚，截止日開關 | ✅ | Toggles | — |

### `forecast`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 圖表在 form sheet 裡寬度剛好，日期刻度不重疊 | ✅ | Charts | — |

### `reimbursement`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 兩個帳戶選擇列、金額、日期、備註（有標籤）在 form sheet 裡一致 | ✅ | Sheets | — |

### `household-leave-confirm`

| 議題 | 結論 | 依據 | 處理 |
|---|---|---|---|
| 確認泡泡出現在畫面最上方、箭頭朝下指著頁首，不是畫面下方的「離開家庭」 | ❌ | Action sheets | #169 |

## 尚未涵蓋

- 橫向、Split View、Slide Over、Stage Manager（視窗寬度變化時的版面）。
- iPad Pro 13 吋與 iPad mini。
- 外接鍵盤、指標、Apple Pencil（#174）。
- 大字級的 iPad 版面：iPhone 那份已涵蓋同一份程式的大字級行為，iPad 沒有另外拍。
- 深色模式每一頁：iPad 只看了三頁，其餘跟淺色同一份程式。
