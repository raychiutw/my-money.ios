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
- 分段控制的字也是 `subheadline`(預設是 13pt,在 composition root 用 appearance 設定)。
  分段控制只用在記一筆、週期收支編輯器導覽列中間的支出／收入，用系統預設的高度，不再用 `.controlSize(.large)` 加高(#65);
  表單裡的其他選擇用表單選擇列，字級是 `body`(見「元件對照」)。
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

## 列與欄位

依 HIG Lists and tables 的「list item titles only, letting people choose an item to reveal its content in a detail view」,以及 Typography 對大字級的建議(研究見 `docs/research/2026-09-29-apple-hig-layout-review.md` §1、§2,#68)。

1. **一行一個欄位**:不同欄位不用「・」「：」串在同一行;需要並列的數字各自一列，用 `LabeledContent`,標籤在左、值在右。
2. **拿掉標籤前綴**:「帳戶：」「記帳人：」「關聯扣款帳戶：」「負債性質拆解：」這類前綴改用位置、圖示或 section 標題表達;VoiceOver 仍念完整標籤。
3. **漸進揭露**:列表列只放辨識和決定需要的資訊(標題加上一到兩個次要欄位),其餘放進點開後的頁面。
4. **截斷**:
   - 點得開的列：標題最多兩行，次要行一行，從結尾截斷。
   - 點不開的列(例如系統紀錄)不截斷，才看得到全文。
   - 長字串(網址)從中間截斷，並提供複製。
5. **大字級**:
   - 左右並列放不下時，改成上下堆疊。
   - 優先用 `LabeledContent`:AX5 截圖證實它會自動堆疊(統計頁的分類列)。
   - 自訂的列用 `ViewThatFits` 依實際空間判斷，不能只看是不是無障礙字級，因為 XXL 不算無障礙字級，卻已經放不下。
   - `LabeledContent` 依 label 不折行的寬度判斷要不要堆疊，所以 label 是會折行的長文字時(例如交易記錄列的備註),預設字級也會堆疊(#72 的截圖)。這種列用 `ViewThatFits`,並給文字欄一個跟著字級變大的最小寬度(`@ScaledMetric`),放得下這個寬度加上金額才左右並列。
   - 金額一律單行，不能被拆成多行(`lineLimit(1)` 加 `fixedSize()`);版面其他部分改成堆疊，把空間讓給金額。
6. **摘要數字**:每頁最多一個主數字(大字),其餘用一般的標籤—值列。
7. **選擇列的值只放名稱**:類型、餘額不放進選擇值;需要時另起一列顯示。
8. **欄位要有看得見的標籤**:placeholder 只放範例，例如「例如：旅遊卡」。
9. **日期**:一律用系統依地區的格式，見「日期」。

研究 §1 建議把次要資訊串成一行再截斷，**不採用**:使用者明確要求不同欄位不要排在同一行，所以用第 1、3 條控制列高。

**交易記錄列**(`TransactionRow`,總覽的最近交易、交易頁共用，#72):

- 前緣是分類圖示。
- 第 1 行：備註，沒有備註時用分類名稱。
- 第 2 行：資產帳戶名稱，不加「帳戶：」。
- 第 3 行：記帳人(`person` symbol 加名稱),只有不是自己記的才顯示。畫面 model 用記帳人的 ID 比對登入的人(家人可能同名),登入的人由 composition root 建立畫面 model 時注入。
- trailing:帶正負號的金額，下面是家庭公帳或個人私帳的標記;系統紀錄在金額前面加鎖定標記。
- 交易頁的列點得開(編輯):備註最多兩行，帳戶、記帳人各一行。系統紀錄和總覽的列點不開，不截斷。
- 用 `ViewThatFits` 排版：圖示、文字欄(最小寬度跟著字級變大)和金額放得下就左右並列;放不下就上下堆疊，圖示和備註一行，帳戶、記帳人、金額、歸屬各一行，用滿整列的寬度。金額一律單行。
- VoiceOver:整列一個元素，念成一句話，依序是分類、備註、帳戶、記帳人、歸屬、收支方向與金額，例如「餐飲，午餐，帳戶 iOS 測試存款，家庭公帳，支出 120 元」。沒有備註時不重複念分類;系統紀錄最後念「系統紀錄，不能編輯或刪除」。
- 交易頁的分組標頭是日期(見「日期」)加當日的收入、支出;放不下時用 `ViewThatFits` 改成上下堆疊。

## 日期

依 HIG Charts 的「using "June 6" is clearer than using "6/6"」,以及 `Date.FormatStyle`「shares the date and time formatting pattern preferred by the user's locale」(研究 §11,#72)。

- 一律用系統依地區的格式(`Date.FormatStyle`),不用 `String(format:)` 自己組，跟 DatePicker 顯示的「2026年9月29日」一致。
- 時區固定台灣(`CalendarDay.timeZone`),跟「今天」「本月」的算法一樣;locale 和曆法跟著系統，使用者把曆法設成民國曆時，跟 DatePicker 一起變。
- wire 上照舊是 `YYYY-MM-DD`(`CalendarDay.iso`),CSV 的檔名也是。

| 用途 | 寫法 | 例 |
|---|---|---|
| 清單裡的日期：儲蓄目標的截止日、現金流預測的最低餘額發生日和預定收支日、家庭群組的代墊明細和加入日期 | `.year().month().day()`;跟今天同一年時省略年份(`.month().day()`) | 2027年3月31日、10月5日 |
| 交易頁的分組標頭 | `.month().day().weekday()`;不是今年的加上年份 | 9月29日週二、2025年12月31日週三 |
| 日期加時間：邀請碼的有效期限 | 清單的日期加 `.hour().minute()` | 10月6日 下午3:00 |
| 月份、年份：統計頁的月份、預算額度 sheet、收支趨勢 | `.year().month()`、`.year()` | 2026年9月、2026年 |

- 已經依日期分組的清單，列內不再重複日期(交易頁)。
- 日期字串由畫面 model 產生(共用的寫法在 `DateText.swift`),model 用 initializer 注入 locale(預設跟著系統)和今天;測試固定用 `zh_Hant_TW` 和注入的日期，不依賴執行當天。
- 聊天泡泡下的時間只有時刻，照裝置的時區。
- 跟 web 的差異見 parity 刻意偏離第 45 項。

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
| 家庭公帳／個人私帳、支出／收入等切換鈕 | **支出／收入：導覽列中間的分段控制**。記一筆和週期收支編輯器放在 sheet 導覽列中間(`.principal` 的 segmented `Picker`),不另外佔表單一列(HIG 分段控制一節舉的行事曆「新增事件」)。**其他選擇：表單選擇列**。記一筆和信用卡扣款還款的歸屬、資產帳戶的歸屬、新增資產帳戶的類型，都是 `Form` 裡一般的 `Picker`(選單樣式):標籤在左、值在右，`body` 字級，跟著 Dynamic Type(#65)。交易頁的視角暫時例外，見「導覽」 |
| `<input type=date>` | `DatePicker(.compact)` |
| 日期文字(`09/29`、`2026/09/28`、`2026-10-05`) | `Date.FormatStyle` 的系統格式，時區固定台灣(見「日期」) |
| `<input type=month>` | 月份 `Picker`(年、月) |
| 金額輸入 | 共用的 `AmountField`:靠右對齊、`.numberPad`、等寬數字，取得焦點時全選(直接輸入就取代原值)。綁定文字，儲存時用 `Money(wholeNumber:)` 解析;鍵盤 toolbar 放「完成」鈕(number pad 沒有 Return 鍵),按下清掉整個表單的焦點：表單的所有文字欄位(包括備註)綁到同一個 focus 狀態，不管焦點在哪個欄位都收起鍵盤;捲動表單也會收起鍵盤(`keyboardDismissal(clearing:)`) |
| 色點選擇器(資產帳戶的代表色) | 8 色的圓形按鈕，每顆觸控範圍至少 44×44 pt;VoiceOver 念顏色的名稱，已選的標記為已選取。**一行放得下就排一行，放不下(例如 iPhone 直向)就改成可以左右滑**,用 `ViewThatFits` 依實際寬度判斷，不看裝置或字級。可以滑的時候，捲動範圍延伸到表單列的兩端，一次看得到六顆半;停下來時對齊色塊的邊界(`viewAligned`),右緣(捲到底時是左緣)一定露出半顆，提示還能滑。打開時用 `scrollPosition` 捲到已選的顏色，打勾完整看得到(編輯既有帳戶也一樣);已選的顏色對齊前緣，不置中，置中時中間的顏色兩端剛好都是完整的圓，看不出還能滑。維持 web 的 8 色，不用系統的 `ColorPicker`:任意顏色是 web 沒有的功能(ADR-0001),所以刻意不採用 HIG「優先用系統色彩控制項」的建議(#71) |
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

系統專用的分類「信用卡還款」(信用卡扣款還款產生的交易記錄)用 `creditcard.and.123`。這類交易記錄不能編輯或刪除，列表上只在 trailing 的金額前面放鎖定標記 `lock.fill`,不放說明文字;VoiceOver 接在交易記錄後面念「系統紀錄，不能編輯或刪除」(見「列與欄位」的交易記錄列)。家庭共同基金的標記用 `house.fill` 加上文字「家庭共同基金」。

## 無障礙

- 觸控目標至少 44×44 pt。
- 金額的 VoiceOver 念法要帶出收支方向，例如「支出 120 元」。
- 列表列整列是一個元素，念成一句完整的話，拿掉的標籤前綴(例如「帳戶」)照樣念出(見「列與欄位」)。
- 圖表的每個元素都要有 accessibility label,另外保留 Swift Charts 預設的 Audio Graph。
- 支援減少動態效果：不做裝飾性的動畫。

## 截圖巡覽

版面用截圖驗收(#68)。`scripts/screen-tour.sh` 用 in-memory 範例資料走過每一頁和主要的 sheet,拍淺色、深色 × 預設、XXL、AX5 字級，共 6 種組合。

- **怎麼跑**:`scripts/screen-tour.sh` 跑全部組合，大約 35 分鐘(AX5 一種組合就要 9 分鐘左右);只跑部分組合用 `-a dark -s ax5` 這類參數，參數說明在 script 開頭。
  - 用專用的模擬器「MyMoney Screen Tour」(iPhone 17,沒有就建立一台),也可以用 `-d` 指定 UDID,不佔用其他測試正在用的模擬器。
  - 建置放在 `.derivedData/screen-tour`,不跟一般測試的建置搶鎖。
  - script 會切換模擬器的外觀、固定狀態列時間，跑完還原。
- **截圖放在哪裡**:預設是 `/tmp/my-money-screen-tour`,用 `-o` 改。截圖不進 repo。
  - 檔名是「外觀-字級-畫面-序號.png」,例如 `dark-ax5-accounts-03.png`。
  - 外觀是 `light`、`dark`;字級是 `default`、`xxl`、`ax5`。
- **範圍**:
  - 登入、註冊、五個 tab(規劃底下的週期收支、儲蓄目標、現金流預測)。
  - 帳號 sheet、家庭群組、機器人記帳、模擬對話。
  - 記一筆、新增資產帳戶(現金錢包、銀行存款帳戶、信用卡)、ATM 提款／轉帳、信用卡扣款還款、新增週期收支、建立儲蓄目標。
  - 可以捲的畫面捲到底，每一屏拍一張(往上拖半個畫面，上下兩張會重疊)。
  - 範例帳號沒有加入家庭群組，家庭群組只拍得到建立和加入。
- **只看不改**:只開畫面、捲動、按「取消」或系統的返回，不按任何儲存或送出。登入用 in-memory 的範例帳號，repo 裡沒有真實帳號或密碼。
- **版面票的 PR**:改之前先跑一次，用 `-o` 存到另一個目錄;改完再跑一次，附上改前改後。
- **維護**:新增畫面或改了入口(例如「+」改成選單)時，一起更新 `tests/MyMoneyUITests/ScreenTourUITests.swift`。
  - 返回一律點系統的返回按鈕。不要點「所有導覽列的第一顆按鈕」:sheet 底下那一層的導覽列也算，會點錯層。
  - 這個測試沒有設 `SCREEN_TOUR_CONTENT_SIZE` 就 skip,一般的 `xcodebuild test` 和 CI 不跑它。

## App icon

- 以 lucide `BookHeart`(ISC 授權)加品牌粉為基礎，用 Icon Composer 做成 Liquid Glass 分層 icon。素材、設計說明和授權聲明在 `design/app-icon/`。
- 深色外觀另外指定顏色：書用 `#FF8A8A`,愛心用 `#FFB3B3`。clear 和 tinted 變體由系統自動產生。
- SF Symbols 的授權不允許用在 app icon。
