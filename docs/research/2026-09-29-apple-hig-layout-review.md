# Apple HIG 版面研究：列表精簡、大字級與控制項（my-money.ios 畫面巡覽後續）

查核日期：2026-09-29（Asia/Taipei）

前置研究：[2026-09-28-apple-hig-ios-app.md](2026-09-28-apple-hig-ios-app.md)（下稱「前一份研究」）。那份已經寫過的通則，例如 tab bar、sheet 按鈕位置、44 pt 觸控目標、對比、swipe 與 context menu 的對應、zh_Hant_TW 貨幣格式，這裡只連回去，不再重述；本文只補更細、更新的依據。

## 研究問題與方法

**問題**：在 iPhone 17 上用預設字級和 XXL 字級截了每個畫面，找出 13 項版面問題（見下表）。產品負責人已經定了 A～D 四項改法。本研究要替每一項找出 HIG 依據、限制，以及對應的 SwiftUI 做法。

**方法**

- 只採用 Apple HIG 和 Apple Developer Documentation。網頁是 JavaScript 渲染的，所以改抓 DocC JSON（`/tutorials/data/design/human-interface-guidelines/<slug>.json`、`/tutorials/data/documentation/<path>.json`）讀全文。API 的最低版本取自 JSON 的 `metadata.platforms[].introducedAt`。行內連結都指向可以直接閱讀的官方網頁。
- 標記沿用前一份研究：**【規定·技術】** 是 Apple 文件寫明的系統行為或 API 可用版本，不照做就達不到效果；**【建議】** 是 HIG 的 best practice；**【推論】** 是套用到本 app 的工程判斷，不是 Apple 原文。HIG 本身沒有審核條文等級的內容，所以本文不會出現單純的【規定】。
- 唯一的本機實測是 §11 的日期格式，在 macOS 27.0 的 Foundation 上執行，歸類為【推論】。
- 本文不是程式碼稽核。只有在需要讓推論更具體時，才讀了相關原始碼（例如 `StatisticsScreen.swift` 的 `.chartLegend(.hidden)`）。

**發現與章節對照**

| # | 發現（摘要） | 章節 |
|---|---|---|
| 1 | 代表色的圓形按鈕超出列寬被裁掉；名稱欄只有 placeholder | §7、§12 |
| 2 | 交易列有 3～4 行、「帳戶：」「記帳人：」前綴、折行 | §1、§2 |
| 3 | 總覽統計卡的公式行；信用卡列兩行、每行串兩個欄位 | §1、§3、§4 |
| 4 | 帳戶頁統計卡太高；信用卡列 9 行資訊加 5 顆按鈕；XXL 時在詞中間斷行 | §2、§3、§4、§5 |
| 5 | Picker 的選擇值太長、被從中間截斷 | §8 |
| 6 | 週期收支統計卡太高；XXL 斷行；「每月繳」重複 | §1、§2、§3 |
| 7 | 儲蓄目標統計卡；「目標 $60,000(5%)」 | §1、§3 |
| 8 | 交易頁 5 列篩選；摘要總額直排；分組標頭是「09/29」 | §3、§6、§11 |
| 9 | 甜甜圈圖沒有圖例；預算一次列出 9 類，每列一顆按鈕 | §5、§10 |
| 10 | 家庭群組的停用按鈕看起來像 placeholder；欄位沒有標籤 | §7、§9 |
| 11 | 機器人記帳有空白列；Webhook 網址折成三行 | §1、§13 |
| 12 | 三種日期格式並存 | §11 |
| 13 | XXL 時從詞中間斷行、文字被截斷 | §2 |

## 結論摘要

1. **§1 列表列**：【建議】列內文字要精簡。資訊一多，就只列標題，其餘放進詳細頁（[Lists and tables › Content](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#Content)）。【推論】一列最多「標題＋一行次要資訊」；「帳戶：」這類前綴拿掉，改由 VoiceOver label 念出。
2. **§2 大字級**：【建議】大字級時改成上下堆疊、減少欄數（[Typography](https://developer.apple.com/design/human-interface-guidelines/typography#Supporting-Dynamic-Type)）。【規定·技術】XXL（`xxLarge`）不屬於 accessibility size，`isAccessibilitySize` 是 false（[DynamicTypeSize](https://developer.apple.com/documentation/swiftui/dynamictypesize)）。【推論】所以要用依實際空間判斷的 `ViewThatFits`，不能只看 `isAccessibilitySize`。
3. **§3 統計摘要**：【推論】每頁只留一個主數字，其餘改成一個欄位一列的 `LabeledContent`；公式行拆成各組成項，收進 `DisclosureGroup` 或詳細頁。
4. **§4 漸進揭露（決策 A）**：【建議】HIG 明文建議「只列標題，點進詳細頁看內容」，並用 disclosure indicator 表示可以點進去（[Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#iOS-iPadOS-visionOS)）。【推論】信用卡詳細頁每個欄位獨立一列。
5. **§5 列內按鈕（決策 A、C）**：【建議】減少畫面上的控制項（[Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios#Best-practices)）；context menu 裡的項目，主介面也要找得到（[Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus#Best-practices)）。【建議】「Add 按鈕帶選單」是 pull-down 的原文範例（[Pull-down buttons](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons#Best-practices)），正好對應「新增預算額度」。
6. **§6 篩選（決策 B）**：【建議】HIG 沒有篩選專章。這裡的依據是 sheet 的「限定任務」（[Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)）、toolbar 項目要精簡（[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars#Best-practices)），以及搜尋要「清楚顯示目前範圍」（[Searching](https://developer.apple.com/design/human-interface-guidelines/searching#Best-practices)）。toolbar 按鈕用標準 Filter 符號 `line.3.horizontal.decrease`（[Icons](https://developer.apple.com/design/human-interface-guidelines/icons#Standard-icons)）。【規定·技術】iPhone 從 iOS 26 起才能用 `navigationSubtitle`（[navigationSubtitle(_:)](https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:))）。
7. **§7 欄位標籤**：【建議】placeholder 在開始輸入後就消失，所以要另外給標籤（[Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields#Best-practices)）。【規定·技術】iOS `Form` 裡的 `TextField` 會把 label 或 prompt 當成 placeholder，不會顯示成標籤（[TextField](https://developer.apple.com/documentation/swiftui/textfield)）；要用 `LabeledContent` 包起來才有看得到的標籤。
8. **§8 Picker**：【推論】選擇值只放短名稱，餘額另外用一列顯示。【規定·技術】`currentValueLabel`（iOS 18）可以讓選項寫得詳細、選擇值維持精簡（[Picker init](https://developer.apple.com/documentation/swiftui/picker/init(selection:content:label:currentvaluelabel:))）。選單項目的副標題，只有 `Menu` 裡的 `Button` 有文件保證（[Menu](https://developer.apple.com/documentation/swiftui/menu)）。
9. **§9 停用按鈕**：【建議】資料不足時停用按鈕是對的（[Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data#Best-practices)）。【推論】但停用時要保留按鈕外形（`.bordered`／`.borderedProminent`），再配上看得到的欄位標籤，就不會跟 placeholder 一樣只剩灰字。
10. **§10 圖表**：【建議】圖例用來說明顏色代表哪個類別（[Charts](https://developer.apple.com/design/human-interface-guidelines/charts#Anatomy)）；同一份資料的多張圖要用同一套顏色（[Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data#Designing-effective-charts)）。【推論】圖表和下方清單也共用同一份顏色對照。【建議】`SectorMark` 文件建議甜甜圈最多 5～7 塊，其餘合併成「其他」（[SectorMark](https://developer.apple.com/documentation/charts/sectormark)）。
11. **§11 日期**：【規定·技術】`Date.FormatStyle` 會依 locale 產生日期字串（[Date.FormatStyle](https://developer.apple.com/documentation/foundation/date/formatstyle)）。【推論】`.abbreviated` 在 zh_Hant_TW 輸出「2026年9月29日」，跟 DatePicker 一樣；分組標頭改用「9月29日週二」，不用「09/29」。
12. **§12 色彩選擇列（決策 D）**：【建議】觸控目標預設 44×44 pt，周圍約 12 pt 間距（[Accessibility › Mobility](https://developer.apple.com/design/human-interface-guidelines/accessibility#Mobility)）。【推論】8 顆在 iPhone 上一行放不下，所以用 `ViewThatFits` 在「一行」和「橫向 ScrollView」之間切換，並自動捲到已選的顏色；維持 web 的 8 色，不改用系統 `ColorPicker`。
13. **§13 空白列與長字串**：【推論】空白列很可能是 `List` 替沒有內容的 view 建了一列。可複製的長字串（Webhook 網址）改成一行、從中間截斷，另附複製按鈕。

## 1. 列表列內容與精簡

**原文依據**

> Keep item text succinct so row content is comfortable to read. Short, succinct text can help minimize truncation and wrapping, making text easier to read and scan.
>
> Sometimes, an ellipsis in the middle of text can make an item easier to distinguish because it preserves both the beginning and the end of the content.（[Lists and tables › Content](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#Content)）

> Avoid truncating text in scrollable regions unless people can open a separate view to read the rest of the content.（[Typography › Supporting Dynamic Type](https://developer.apple.com/design/human-interface-guidelines/typography#Supporting-Dynamic-Type)）

**中文重點**

- 【建議】列內文字要精簡，才能減少截斷和折行（[Lists and tables › Content](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#Content)）。
- 【建議】需要截斷時，可以把省略號放在中間，同時保留開頭和結尾，比較好分辨（[Lists and tables › Content](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#Content)）。
- 【建議】「Check each word to be sure it needs to be there. If you can use fewer words, do so.」（[Writing › Getting started](https://developer.apple.com/design/human-interface-guidelines/writing#Getting-started)）
- 【建議】可捲動區域裡的文字，只有在「點進去看得到全文」時才可以截斷（[Typography › Supporting Dynamic Type](https://developer.apple.com/design/human-interface-guidelines/typography#Supporting-Dynamic-Type)）。
- 【規定·技術】`lineLimit(_:)` 對 hierarchy 裡的每個 `Text` 各自生效（「caps each piece of text … rather than capping the total」）（[lineLimit(_:)](https://developer.apple.com/documentation/swiftui/view/linelimit(_:)-513mb)）。`Text.TruncationMode` 可以從開頭、中間或結尾截斷（[Text.TruncationMode](https://developer.apple.com/documentation/swiftui/text/truncationmode)）。

**對本 app 的建議（【推論】）**

- **產品決策（2026-09-29，#68）**：使用者明確要求「不同欄位不要排在同一行」，所以 spec 不採用下一條「次要資訊串成一行再截斷」的做法，改成一行一個欄位，再用漸進揭露控制列高。本段保留研究當時的推論，供日後參考。
- **交易列（發現 2）**：每列最多兩行。第 1 行放分類（`lineLimit(1)`），trailing 放金額；第 2 行放備註・帳戶・記帳人，拿掉「帳戶：」「記帳人：」前綴，設 `lineLimit(1)`、從結尾截斷。點列會進編輯表單看到全文，符合 Typography 的截斷條件。
- **VoiceOver 念回前綴**：用 `accessibilityElement(children: .ignore)` 加 `accessibilityLabel`，念出「帳戶 …，記帳人 …」（[accessibilityElement(children:)](https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:))）。「信用卡還款」列不能編輯，沒有可以看全文的畫面，所以不截斷（`lineLimit(nil)`）。
- **週期收支列（發現 6）**：右側的「每月繳」跟左側「每月 5 號扣款」重複，拿掉。「關聯扣款帳戶：」前綴比照交易列處理。
- **儲蓄目標（發現 7）**：「目標 $60,000(5%)」改成「已存／目標」兩個金額，加上進度條；百分比交給 `ProgressView` 或 `Gauge` 表達。Gauge 的 label 要能描述目前的值和範圍兩端（[Gauges › Best practices](https://developer.apple.com/design/human-interface-guidelines/gauges#Best-practices)）。
- 總覽的信用卡列（發現 3）見 §4；Webhook 網址（發現 11）見 §13。

## 2. 大字級版面（stacked layout、ViewThatFits、isAccessibilitySize）

**原文依據**

> Consider adjusting your layout at large font sizes. When font size increases in a horizontally constrained context, inline items (like glyphs and timestamps) and container boundaries can crowd text and cause truncation or overlapping. To improve readability, consider using a stacked layout where text appears above secondary items.（[Typography › Supporting Dynamic Type](https://developer.apple.com/design/human-interface-guidelines/typography#Supporting-Dynamic-Type)）

> For example, horizontally adjacent views may need to stack vertically to provide more space for text; table rows or other containers may need to grow in height so that text isn’t cropped or doesn’t overlap other content（[Layout › Adaptability](https://developer.apple.com/design/human-interface-guidelines/layout#Adaptability)）

> `ViewThatFits` evaluates its child views in the order you provide them to the initializer. It selects the first child whose ideal size on the constrained axes fits within the proposed size.（[ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits)）

**中文重點**

- 【建議】大字級時改用 stacked layout（文字在上、次要項目在下），並減少欄數（[Typography › Supporting Dynamic Type](https://developer.apple.com/design/human-interface-guidelines/typography#Supporting-Dynamic-Type)）。
- 【建議】「Prioritize important content when responding to text-size changes」：使用者放大字，不代表每個字都要跟著放大（[Typography › Conveying hierarchy](https://developer.apple.com/design/human-interface-guidelines/typography#Conveying-hierarchy)）。
- 【規定·技術】`DynamicTypeSize` 有 7 個標準尺寸（`xSmall`…`xxxLarge`）和 5 個 accessibility 尺寸（`accessibility1`…`accessibility5`）。`isAccessibilitySize` 只有在後 5 個尺寸時才是 true（[DynamicTypeSize](https://developer.apple.com/documentation/swiftui/dynamictypesize)、[isAccessibilitySize](https://developer.apple.com/documentation/swiftui/dynamictypesize/isaccessibilitysize)）。
- 【規定·技術】HIG 的字級表：Body 在預設 Large 是 17 pt，xxLarge 是 21 pt，AX5 是 53 pt（[Typography › Specifications](https://developer.apple.com/design/human-interface-guidelines/typography#Specifications)）。
- 【規定·技術】`AnyLayout`「enable[s] dynamically changing the type of a layout container without destroying the state of the subviews」，文件範例是依 `dynamicTypeSize` 在 `HStackLayout` 和 `VStackLayout` 之間切換（[AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout)）。

**對本 app 的建議（【推論】）**

- **XXL 不算 accessibility 尺寸**：巡覽用的 XXL 如果是 `UICTContentSizeCategoryXXL`，對應的是 `DynamicTypeSize.xxLarge`（標準尺寸的第 6 級），這時 `isAccessibilitySize` 是 false。用它當開關的堆疊版面，在 XXL 不會生效。
- **XXL 壞了，AX5 會更糟**：XXL 只比預設大約 24%（Body 從 17 pt 到 21 pt）。在 XXL 就已經壞掉的版面，到 AX5（53 pt）會更嚴重。
- **版面切換的做法**：預設用 `ViewThatFits(in: .horizontal)` 依實際空間切換。只有「一定要在 accessibility 尺寸改版」時，才讀 `isAccessibilitySize`。DESIGN.md 已經用 `ViewThatFits` 處理還款按鈕，沿用同一個做法。
- **一行兩個欄位要拆開**：「結帳日…・繳款日…」「未指定關聯帳戶・週期攤提 $2,000 / 月」這類（發現 4、6、13），根本的解法是一個欄位一列（`LabeledContent`，見 §3、§4），只靠換行解決不了。
- **中文從詞中間斷行**：本次沒有在 Apple 文件裡找到讓 SwiftUI `Text` 依中文詞斷行的設定（見「未查證」）。能做的是在結構上避免長串接：每個欄位用獨立的 `Text` 或獨立一列，標籤盡量短。
- **金額不要斷成兩行**：金額的 `Text` 設 `lineLimit(1)`，再加上 `minimumScaleFactor`。文件說這個 modifier 適用於「it’s okay if the text shrinks to accommodate」的情況（[minimumScaleFactor(_:)](https://developer.apple.com/documentation/swiftui/view/minimumscalefactor(_:))）。版面其他部分改成堆疊，把空間讓給金額。
- **測試矩陣加上 AX5**：HIG 建議先測最大和最小的版面（見前一份研究 §4）。目前的巡覽只有預設和 XXL 兩種字級。

## 3. 統計摘要的呈現（大數字 vs 一般列）

**原文依據**

> Use progressive disclosure to make layouts cleaner and easier to interact with.（[Layout › Visual hierarchy](https://developer.apple.com/design/human-interface-guidelines/layout#Visual-hierarchy)）

> Not all content is equally important. When someone chooses a larger text size, they typically want to make the content they care about easier to read; they don’t always want to increase the size of every word on the screen.（[Typography › Conveying hierarchy](https://developer.apple.com/design/human-interface-guidelines/typography#Conveying-hierarchy)）

> Use a disclosure control to hide details until they’re relevant.（[Disclosure controls › Best practices](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls#Best-practices)）

**中文重點**

- 【建議】內容要依重要性排序，最重要的放在上方和 leading 側（「Order content by relative importance」，[Layout › Visual hierarchy](https://developer.apple.com/design/human-interface-guidelines/layout#Visual-hierarchy)）。
- 【建議】disclosure triangle 要附描述性的 label，寫明它展開的是什麼內容（[Disclosure controls › Disclosure triangles](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls#Disclosure-triangles)）。
- 【規定·技術】`LabeledContent` 可以直接用字串或格式化的值，做出唯讀的文字列。它的版面「automatically adapts to its container, like a form」，而且「Wherever possible, SwiftUI makes this text selectable」（[LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent)）。

**對本 app 的建議（【推論】）**

- **每頁只留一個主數字**：總覽是「淨可用餘額」。帳戶頁、週期收支、儲蓄目標各留哪一個，由產品負責人決定。
- **其餘數字改成列**：放進一個 `Section`，每個數字一列 `LabeledContent`（label 在左，金額在右並加 `.monospacedDigit()`）。原本 3～4 張高卡片，會變成幾列一般高度的列。
- **公式行拆開**：「現金 $0 + 銀行存款 $50,000 - 待繳卡費 $28,500」拆成 3 列 `LabeledContent`，放進 `DisclosureGroup("計算方式")`（[DisclosureGroup](https://developer.apple.com/documentation/swiftui/disclosuregroup)）；或者點主數字 push 到明細頁。
- **交易頁摘要（發現 8）**：「4 筆」和三個直排的總額，改成 3 列 `LabeledContent`（收入、支出、淨額）。
- **功能對等**：web 有的數字和公式內容全部保留，只是改用漸進揭露呈現，屬於互動層的轉譯。依 CLAUDE.md，每一處跟 web 不同的地方都要記進 `docs/parity.md`。

## 4. 漸進揭露與詳細頁（決策 A）

**原文依據**

> If each item consists of a large amount of text, consider alternatives that help you avoid displaying over-large table rows. For example, you could list item titles only, letting people choose an item to reveal its content in a detail view.（[Lists and tables › Content](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#Content)）

> If you need to let people drill into a list or table row’s subviews, use a disclosure indicator accessory control.（[Lists and tables › iOS, iPadOS, visionOS](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#iOS-iPadOS-visionOS)）

> Help people concentrate on primary tasks and content by limiting the number of onscreen controls while making secondary details and actions discoverable with minimal interaction.（[Designing for iOS › Best practices](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios#Best-practices)）

**中文重點**

- 【建議】列表只放標題，細節放到詳細頁；可以點進去的列要顯示 disclosure indicator。info button 只用來顯示資訊，不能拿來導覽（[Lists and tables › iOS, iPadOS, visionOS](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#iOS-iPadOS-visionOS)）。
- 【建議】減少畫面上的控制項，次要的細節和動作「一兩下就找得到」即可（[Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios#Best-practices)）。
- 【規定·技術】以值驅動的導覽用 `NavigationLink(value:)` 加上 `navigationDestination(for:destination:)`，iOS 16 起可用（[NavigationLink](https://developer.apple.com/documentation/swiftui/navigationlink)、[navigationDestination(for:destination:)](https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:))）。`LabeledContent` 可以當 `NavigationLink` 的 label，「present a summary value for the destination it links to」（[LabeledContent › Compositional elements](https://developer.apple.com/documentation/swiftui/labeledcontent)）。

**對本 app 的建議（【推論】）**

- **信用卡精簡列**：代表色、名稱，trailing 放待繳卡費；第 2 行只放一項，例如「每月 5 日繳款」或「卡費已全數結清」。整列是 `NavigationLink(value: card.id)`。總覽「帳戶一覽」的信用卡列（發現 3）也用同一種精簡列，點進去是同一個詳細頁。
- **信用卡詳細頁（push）**：每個欄位一列 `LabeledContent`。
  - `Section`「卡費」：待繳卡費、家庭代墊公帳、個人私帳消費、未出帳。發現 4 的「負債性質拆解」這一行就此消失。
  - `Section`「設定」：信用額度、結帳日「每月 15 日」、繳款日「每月 5 日」。
  - `Section`「操作」：繳款、出帳作業、校準未出帳（見 §5）。
  - toolbar 的 trailing 放「編輯」。HIG 允許 edit 這類難用符號表達的動作使用文字（「except for actions like edit that aren’t well-represented by symbols」，[Toolbars › Actions](https://developer.apple.com/design/human-interface-guidelines/toolbars#Actions)）。
- **畫面 model 的建立**：依 CLAUDE.md「畫面 model 由父層或路由建立後傳入」，在 `navigationDestination` 裡建立詳細頁的 model。
- **文件要同步更新**：DESIGN.md「信用卡的三個還款入口是 borderless 按鈕排成一排」這段要改，parity.md 也要記錄這項偏離。

## 5. 列內按鈕、swipe、context menu 與預算清單（決策 A、C）

**原文依據**

> Always make context menu items available in the main interface, too.（[Context menus › Best practices](https://developer.apple.com/design/human-interface-guidelines/context-menus#Best-practices)）

> An Add button could present a menu that lets people specify the item they want to add.
>
> Avoid putting all of a view’s actions in one pull-down button.
>
> Because people have to interact with a pull-down button before they can view its menu, listing a minimum of three items can help the interaction feel worthwhile.（[Pull-down buttons › Best practices](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons#Best-practices)）

> Offer alternatives to gestures. Make sure your UI’s core functionality is accessible through more than one type of physical interaction.（[Accessibility › Mobility](https://developer.apple.com/design/human-interface-guidelines/accessibility#Mobility)）

**中文重點**

- 【建議】context menu 的項目要少，而且只放目前情境最可能用到的；暫時不能用的項目要隱藏，不要變灰（「Hide unavailable menu items, don’t dim them」，[Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus#Best-practices)）。context menu 最上方的項目要跟 swipe actions 一致，見前一份研究 §7.1。
- 【建議】需要更多資訊才能完成的選單項目，label 後面加省略號（[Menus › Labels](https://developer.apple.com/design/human-interface-guidelines/menus#Labels)）。
- 【建議】一個畫面的 prominent 按鈕以一到兩顆為限（[Buttons › Style](https://developer.apple.com/design/human-interface-guidelines/buttons#Style)）。
- 【建議】「You can help make a long list more manageable by listing the most relevant items and providing a way for people to view more.」這句出自 Lists 頁的 watchOS 一節（[Lists and tables › watchOS](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#watchOS)）；套用到 iPhone 是【推論】。
- 【規定·技術】「By default, the user can perform the first action for a given swipe direction with a full swipe」，可以用 `allowsFullSwipe: false` 關掉（[swipeActions(edge:allowsFullSwipe:content:)](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:))）。

**對本 app 的建議（【推論】）**

- **決策 A 的動作配置**：詳細頁是「主介面」，所有動作都在這裡。精簡列只放捷徑：leading swipe 放「繳款」，context menu 放繳家庭代墊、繳個人私帳、全額結清、出帳作業；這些在詳細頁都找得到，符合「context menu 的項目主介面也要有」。
- **決策 A 的「繳款」**：三個還款動作剛好 3 項，詳細頁用一顆「繳款」pull-down（`Menu`），滿足「至少三項」；出帳作業、校準未出帳是各自獨立的按鈕，不全塞進 pull-down。
- **決策 C（發現 9）**：預算只列「有預算」或「本月有支出」的分類。整列就是一顆 `Button`，點了開調整 sheet，不再放「設定／調整」文字按鈕，觸控目標從一小顆文字變成整列。VoiceOver label 念出「餐飲，預算 X，已用 Y」。
- **決策 C 的「新增預算額度」**：其餘分類收進 `Section` 底部的 `Menu`，正是 HIG「Add 按鈕帶選單」的原文範例。選單項目是分類名稱，選了開同一個設定 sheet，label 可依 Menus 指引加「…」。全部分類都已有預算時不顯示。
- **功能對等**：web 一次列出 9 類，iOS 只列一部分，但沒列出來的仍可以從新增選單進入。這屬於互動層轉譯，要記進 parity.md。

## 6. 篩選的呈現（決策 B）

**原文依據**

> A sheet helps people perform a scoped task that’s closely related to their current context.
>
> In an iPhone app, consider supporting the medium detent to allow progressive disclosure of the sheet’s content.（[Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets#iOS-iPadOS)）

> Clearly display the current scope of a search.（[Searching › Best practices](https://developer.apple.com/design/human-interface-guidelines/searching#Best-practices)）

> A view’s navigation subtitle is used to provide additional contextual information alongside the navigation title. … On iOS and iPadOS, the subtitle is displayed with the navigation title in the navigation bar.（[navigationSubtitle(_:)](https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:))）

**中文重點**

- 【建議】pop-up button 適合「a flat list of mutually exclusive options」（[Pop-up buttons › Best practices](https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons#Best-practices)）。HIG 沒有篩選專章；最接近的是搜尋的 scope bar 和 token（見前一份研究 §1.4）。
- 【建議】sheet 有 Done 就一定要配 Cancel（[Sheets › Best practices](https://developer.apple.com/design/human-interface-guidelines/sheets#Best-practices)）。可以調整高度的 sheet 要加 grabber（[Sheets › iOS, iPadOS](https://developer.apple.com/design/human-interface-guidelines/sheets#iOS-iPadOS)）。modal 要讓人看得出它的任務是什麼（「Make it easy to identify a modal view’s task」，[Modality](https://developer.apple.com/design/human-interface-guidelines/modality#Best-practices)）。
- 【建議】toolbar 的項目要精選，偏好沒有外框的系統符號（「Prefer system-provided symbols without borders」，[Toolbars › Actions](https://developer.apple.com/design/human-interface-guidelines/toolbars#Actions)）。Filter 的標準符號是 `line.3.horizontal.decrease`（[Icons › Standard icons](https://developer.apple.com/design/human-interface-guidelines/icons#Standard-icons)）。
- 【規定·技術】`navigationSubtitle(_:)` 在 iOS／iPadOS 26.0 才開放（macOS 早就有）；本 app 最低 iOS 26.0，可以直接用（[navigationSubtitle(_:)](https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:))）。
- 【規定·技術】`.menu` picker style 的文件寫著「Use this style when there are more than five options」（[PickerStyle.menu](https://developer.apple.com/documentation/swiftui/pickerstyle/menu)）。`DatePicker` 可以限制可選的日期範圍（[DatePicker](https://developer.apple.com/documentation/swiftui/datepicker)）。

**對本 app 的建議（【推論】）**

- **為什麼用 sheet**：交易頁的篩選有 4 個維度，其中日期區間需要 DatePicker，一個選單放不下，所以用 sheet 比 pull-down 或 pop-up 合適。
- **toolbar 按鈕**：`Button("篩選", systemImage: "line.3.horizontal.decrease")`，不要用 `.circle` 變體。點了開「篩選」sheet，設 `presentationDetents([.medium, .large])` 並顯示 grabber（[presentationDetents(_:)](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:))、[presentationDragIndicator(_:)](https://developer.apple.com/documentation/swiftui/view/presentationdragindicator(_:))）。
- **sheet 內容**：視角（segmented，3 段）、起日與迄日（compact 樣式的 DatePicker，迄日設 `in: start...`）、類型（segmented）、分類（`.menu` 樣式的 Picker，超過 5 項），加一顆「重設為本月」按鈕。
- **取消＋完成**：sheet 編輯的是一份草稿，按「完成」才套用。這樣只會發一次 API 請求；如果每改一項就重查，會連續打好幾次 API。
- **副標題**：`navigationSubtitle` 顯示目前的範圍，例如「家庭・9月1日–9月30日・支出・餐飲」。用預設值（本月、全部）時也顯示月份，讓範圍一直看得見。兩個日期成對時，[Date.FormatStyle](https://developer.apple.com/documentation/foundation/date/formatstyle) 的文件指向 `IntervalFormatStyle`。
- **DESIGN.md 要改**：DESIGN.md 規定總覽、交易、統計頁頂端都有視角 segmented Picker。決策 B 把交易頁的視角收進 sheet，所以那一條要加上交易頁的例外。

## 7. 表單欄位標籤與 placeholder

**原文依據**

> Because placeholder text disappears when people start typing, it can also be useful to include a separate label describing the field to remind people of its purpose.（[Text fields › Best practices](https://developer.apple.com/design/human-interface-guidelines/text-fields#Best-practices)）

> If your app allows people to enter their own text, like account or contact information, label all fields clearly, and use hint or placeholder text so people know how to format the information.（[Writing › Best practices](https://developer.apple.com/design/human-interface-guidelines/writing#Best-practices)）

> In the same context on iOS, the text field uses either the prompt or label as placeholder text, depending on whether the initializer provided a prompt.（[TextField › Text field prompts](https://developer.apple.com/documentation/swiftui/textfield)）

**中文重點**

- 【建議】每個欄位都要有清楚的標籤；placeholder 用來給範例或格式提示（[Writing](https://developer.apple.com/design/human-interface-guidelines/writing#Best-practices)）。
- 【規定·技術】在 iOS 的 `Form` 裡，`TextField` 的 label 不會顯示成欄位標籤：有 prompt 時用 prompt 當 placeholder，沒有 prompt 時用 label 當 placeholder（[TextField](https://developer.apple.com/documentation/swiftui/textfield)、[init(text:prompt:label:)](https://developer.apple.com/documentation/swiftui/textfield/init(text:prompt:label:))）。
- 【規定·技術】`LabeledContent` 可以包住自訂 view，而且「has a layout that matches the label of the Picker」（[LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent)）。

**對本 app 的建議（【推論】）**

- **資產帳戶表單（發現 1）**：改成 `LabeledContent("名稱") { TextField("名稱", text: $name, prompt: Text("例如：旅遊卡")) }`。這樣「名稱」一直看得到，placeholder 繼續提供範例。
- **家庭群組（發現 10）**：家庭名稱、邀請碼兩個欄位比照處理。如果一個 `Section` 只有一個欄位，也可以直接用 Section header 當標籤。
- 大字級時 `LabeledContent` 會不會自動改成上下排列，文件沒有說明，要實測（見「未查證」）。

## 8. Picker／pop-up 的選擇值與選單項目副標題

**原文依據**

> Give people a way to predict a pop-up button’s options without opening it.（[Pop-up buttons › Best practices](https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons#Best-practices)）

> The button itself indicates the selected option.（[PickerStyle.menu](https://developer.apple.com/documentation/swiftui/pickerstyle/menu)）

> To support subtitles on menu items, initialize your `Button` with a view builder that creates multiple `Text` views where the first text represents the title and the second text represents the subtitle.（[Menu](https://developer.apple.com/documentation/swiftui/menu)，同頁註記：「This behavior does not apply to buttons outside of a menu’s content.」）

**中文重點**

- 【規定·技術】`Picker(selection:content:label:currentValueLabel:)` 在 iOS 18.0 起可用：「Creates a picker that displays a custom label and a custom value label where applicable」。官方範例用 `.navigationLink` 樣式，選項是多行的 VStack（歌名、歌手、類型），`currentValueLabel` 只顯示歌名（[init(selection:content:label:currentValueLabel:)](https://developer.apple.com/documentation/swiftui/picker/init(selection:content:label:currentvaluelabel:))）。
- 【建議】「In navigation stacks, prefer the default menu style. Consider the navigation link style when you have a large number of options」（[PickerStyle.navigationLink](https://developer.apple.com/documentation/swiftui/pickerstyle/navigationlink)）。HIG 也說「Avoid switching views to show a picker」（[Pickers › Best practices](https://developer.apple.com/design/human-interface-guidelines/pickers#Best-practices)）。
- 【規定·技術】`Picker` 的 label 可以用兩個 `Text` 組成標題和副標題（[Picker](https://developer.apple.com/documentation/swiftui/picker)）。

**對本 app 的建議（【推論】）**

- **選項只放帳戶名稱（發現 5）**：例如「iOS 測試存款」，拿掉「(銀行存款帳戶)」。
- **餘額另起一列**：轉帳時不要把餘額塞進選項文字。在 Picker 的下一列用 `LabeledContent("可用餘額", value: …)` 顯示所選帳戶的餘額，一個欄位一列。
- **一定要在選項裡顯示類型或餘額時**：用 `currentValueLabel`（iOS 18，本 app 可用）讓選擇值只顯示名稱。`.menu` 樣式下 Picker 選項能不能顯示副標題，文件沒有保證，要實機驗證；`.navigationLink` 樣式有文件範例，但會切換畫面，帳戶數量不多時不建議。
- **XXL 時 label 被擠到值上方**：這是 Form 的系統版面行為（未查到文件，屬推論）。值縮短後自然會改善。

## 9. 按鈕樣式與停用狀態

**原文依據**

> When data entry is necessary, make sure people understand that they must provide the required data before they can proceed. For example, if you include a Next or Continue button after a set of text fields, make the button available only after people enter the data you require.（[Entering data › Best practices](https://developer.apple.com/design/human-interface-guidelines/entering-data#Best-practices)）

> Avoid using the same color to mean different things.（[Color › Best practices](https://developer.apple.com/design/human-interface-guidelines/color#Best-practices)）

**中文重點**

- 【建議】必填資料還沒填完時，停用送出按鈕是正確做法（[Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data#Best-practices)）。
- 【建議】系統替這兩種用途定了不同的語意色：tertiary label 是「Text that describes an unavailable item or behavior」（[Labels › Best practices](https://developer.apple.com/design/human-interface-guidelines/labels#Best-practices)），placeholder text 是「Placeholder text in controls or text views」（[Color › iOS, iPadOS](https://developer.apple.com/design/human-interface-guidelines/color#iOS-iPadOS)）。兩者看起來都是灰字。
- 【建議】「Use style — not size — to visually distinguish the preferred choice among multiple options.」（[Buttons › Style](https://developer.apple.com/design/human-interface-guidelines/buttons#Style)）

**對本 app 的建議（【推論】）**

- **問題在外形，不在停用（發現 10）**：`Form` 裡純文字的按鈕停用後只剩灰字，跟上一列欄位的 placeholder 一樣都是灰色文字，看不出哪個是按鈕。
- **做法**：(1) 欄位加上看得到的標籤（§7）；(2) 「建立家庭群組」「加入家庭群組」改用 `.buttonStyle(.bordered)`，主要動作用 `.borderedProminent`（[bordered](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/bordered)、[borderedProminent](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/borderedprominent)），停用時仍保有按鈕外形；(3) 用 Section footer 說明啟用條件，例如「輸入家庭名稱後就能建立」。
- **分成兩個 Section**：建立和加入是兩條互斥的路，各用一個 `Section`，各有一個欄位、一顆按鈕。兩顆都用 prominent 樣式，仍在「一個畫面一到兩顆」的上限內。
- **停用狀態沿用系統外觀**：不要自己替停用按鈕另外配色，以免改變系統語意色的意義（前一份研究 §3.2）。

## 10. 圖表的圖例與顏色

**原文依據**

> When needed, you can also create a legend, which describes chart properties that aren’t related to a mark’s position, such as the use of color or shape to denote different value categories.（[Charts › Anatomy](https://developer.apple.com/design/human-interface-guidelines/charts#Anatomy)）

> When you use multiple charts to help people explore one dataset from different perspectives, it’s important to use one chart type and consistent colors, annotations, layouts, and descriptive text to signal that the dataset remains the same.（[Charting data › Designing effective charts](https://developer.apple.com/design/human-interface-guidelines/charting-data#Designing-effective-charts)）

> To ensure that the visualization is easy to read, design pie or donut charts with no more than 5-7 sectors. Sum any remaining values into an “Other” group if necessary, or consider horizontal bar charts（[SectorMark](https://developer.apple.com/documentation/charts/sectormark)）

**中文重點**

- 【建議】圖例的用途，就是說明顏色或形狀代表哪個類別（[Charts › Anatomy](https://developer.apple.com/design/human-interface-guidelines/charts#Anatomy)）。同一份資料用多張圖呈現時，顏色要一致（[Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data#Designing-effective-charts)）；把這條延伸到「圖表和下方清單」是【推論】。不能只靠顏色，見前一份研究 §8。
- 【規定·技術】`foregroundStyle(by:)` 會自動配色，並且「adds a legend to indicate which color represents which kind of data」。要指定哪個類別用哪個顏色，用 `chartForegroundStyleScale(_:)`（[Creating a chart using Swift Charts](https://developer.apple.com/documentation/charts/creating-a-chart-using-swift-charts)、[chartForegroundStyleScale(domain:range:type:)](https://developer.apple.com/documentation/swiftui/view/chartforegroundstylescale(domain:range:type:))）。

**對本 app 的建議（【推論】）**

- **現況（發現 9）**：`StatisticsScreen.swift` 的甜甜圈用 `foregroundStyle(by: .value("分類", …))`，又加了 `.chartLegend(.hidden)`。顏色是系統自動指派的，下方清單又沒有對應的顏色，看不出哪塊是哪個分類。
- **兩種改法擇一**：(a) 拿掉 `.chartLegend(.hidden)`，顯示系統圖例；(b) 繼續隱藏圖例，但清單每列前緣加一個同色圓點，讓清單兼當圖例。顏色必須來自同一份 `chartForegroundStyleScale(domain:range:)` 對照表，不能讓圖表和清單各自配色。建議 (b)：比較省空間，而且清單本來就有分類名稱和金額，不會只靠顏色傳達資訊。
- **分類太多時**：分類超過 7 個，把比例很小的合併成「其他」，或改用水平 bar（前一份研究 §8 已經建議）。

## 11. 日期格式（locale、Date.FormatStyle）

**原文依據**

> A date format style shares the date and time formatting pattern preferred by the user’s locale for formatting and parsing.
>
> When displaying a date to a user, use the `formatted(date:time:)` instance method.（[Date.FormatStyle](https://developer.apple.com/documentation/foundation/date/formatstyle)）

> The exact values shown in a date picker, and their order, depend on the device location.（[Pickers › iOS, iPadOS](https://developer.apple.com/design/human-interface-guidelines/pickers#iOS-iPadOS)）

**中文重點**

- 【建議】日期格式屬於依 locale 變化的國際化項目（[Layout › Adaptability](https://developer.apple.com/design/human-interface-guidelines/layout#Adaptability)）。「Build language patterns. Consistency builds familiarity」（[Writing › Best practices](https://developer.apple.com/design/human-interface-guidelines/writing#Best-practices)）。
- 【建議】HIG 在圖表無障礙一節指出「using “June 6” is clearer than using “6/6”」（[Charts › Enhancing the accessibility of a chart](https://developer.apple.com/design/human-interface-guidelines/charts#Enhancing-the-accessibility-of-a-chart)）。這句針對的是 accessibility label；套用到畫面上的分組標頭是【推論】。
- 【規定·技術】`Date.FormatStyle(date:time:locale:calendar:timeZone:capitalizationContext:)` 可以指定 time zone 和 calendar。DateStyle 有 `.numeric`、`.abbreviated`、`.long`、`.complete`（[init](https://developer.apple.com/documentation/foundation/date/formatstyle/init(date:time:locale:calendar:timezone:capitalizationcontext:))、[formatted(date:time:)](https://developer.apple.com/documentation/foundation/date/formatted(date:time:))）。

**本機實測（【推論】；macOS 27.0 Foundation，locale `zh_Hant_TW`、Asia/Taipei、gregorian，日期 2026-09-29；iOS 27 未實測）**

| 寫法 | 輸出 |
|---|---|
| `Date.FormatStyle(date: .numeric, time: .omitted)` | `2026/9/29` |
| `date: .abbreviated`／`.long` | `2026年9月29日` |
| `date: .complete` | `2026年9月29日星期二` |
| `Date.FormatStyle().month().day().weekday()` | `9月29日週二` |
| `Date.FormatStyle().month().day()` | `9月29日` |
| `Date.FormatStyle().month(.defaultDigits).day()` | `9/29` |

**對本 app 的建議（【推論】）**

- **現況（發現 12）**：`TransactionsScreen.swift`、`AmountInput.swift`、`HouseholdModel.swift` 都用 `String(format:)` 自己組日期字串。
- **為什麼要改**：DatePicker 的格式由系統依 locale 決定，app 改不了。要讓三處一致，唯一的辦法是讓自己的文字也改走 FormatStyle。
- **清單裡的日期**：用 `.abbreviated`，跟 DatePicker 一樣是「2026年9月29日」。同一年內的日期可以省略年份，用 `.month().day()`。
- **分組標頭**：用 `.month().day().weekday()`，顯示「9月29日週二」。已經依日期分組的清單，列內就不要再重複日期。
- **時區與曆法**：time zone 一律固定為 Asia/Taipei（CLAUDE.md 的日期規則）；calendar 和 locale 跟隨系統。使用者如果把曆法設成民國曆，app 的日期會跟 DatePicker 一起變成民國曆，兩者仍然一致。wire 上的日期維持 `YYYY-MM-DD`。
- **功能對等**：web 用的是「MM/DD」「YYYY/MM/DD」。改成 locale 格式屬於互動層轉譯，要記進 parity.md。

## 12. 觸控目標與色彩選擇列（決策 D）

**原文依據**

> In general, it works well to add about 12 points of padding around elements that include a bezel. For elements without a bezel, about 24 points of padding works well around the element’s visible edges.（[Accessibility › Mobility](https://developer.apple.com/design/human-interface-guidelines/accessibility#Mobility)，同節表格：iOS 的預設控制項尺寸 44×44 pt，最小 28×28 pt）

> Make it apparent when content is scrollable. … For example, displaying partial content at the edge of a view indicates that there’s more content in that direction.
>
> It’s alright to place a horizontal scroll view inside a vertical scroll view (or vice versa), however.
>
> In some cases, scroll automatically to help people find their place.（[Scroll views › Best practices](https://developer.apple.com/design/human-interface-guidelines/scroll-views#Best-practices)）

> If your app lets people choose colors, prefer system-provided color controls where available.（[Color › Best practices](https://developer.apple.com/design/human-interface-guidelines/color#Best-practices)；[Color wells](https://developer.apple.com/design/human-interface-guidelines/color-wells#Best-practices) 也寫「Consider the system-provided color picker for a familiar experience」）

**中文重點**

- 【建議】可以捲動的內容，要讓人看得出來能捲；露出半個項目就是一種提示。垂直捲動的畫面裡放橫向 ScrollView 是可以的。相關內容不在畫面上時，可以自動捲過去（[Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views#Best-practices)）。
- 【建議】app 讓使用者選顏色時，優先用系統的色彩控制項（[Color](https://developer.apple.com/design/human-interface-guidelines/color#Best-practices)）。
- 【規定·技術】`scrollPosition(id:anchor:)` 要搭配 `scrollTargetLayout()` 使用，iOS 17 起可用（[scrollPosition(id:anchor:)](https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:))、[scrollTargetLayout(isEnabled:)](https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:))）。

**對本 app 的建議（【推論】）**

- **算一下寬度**：8 × 44 pt + 7 × 12 pt = 436 pt；就算完全不留間距也要 352 pt。iPhone 直向時，表單列扣掉邊距放不下（截圖已經看到被裁）；iPad 或橫向則可能放得下。這正好是 `ViewThatFits(in: .horizontal) { HStack { 色塊 } ; ScrollView(.horizontal) { HStack { 色塊 } } }` 適合的情境。
- **現況最糟**：色塊列不能捲動，兩端又被裁成半顆，看起來像可以捲，其實不能，剛好違反 Scroll views 對捲動提示的原意；最左、最右兩顆也拿不到完整的 44 pt 可點範圍。
- **橫向捲動版的細節**：用 `contentMargins(.horizontal, …, for: .scrollContent)` 讓右緣露出部分色塊，提示還能往右捲（[contentMargins(_:_:for:)](https://developer.apple.com/documentation/swiftui/view/contentmargins(_:_:for:))）。進入畫面時用 `scrollPosition(id:)` 把已選的顏色捲進可視範圍，因為編輯既有帳戶時它可能在畫面外。已選的打勾要畫在 44 pt 的框內，不能被裁掉。
- **不改用系統 `ColorPicker`**：HIG 建議用系統的色彩控制項，但 web 只提供 8 種固定的代表色（parity.md，W:utils.ts:54-55）。[`ColorPicker`](https://developer.apple.com/documentation/swiftui/colorpicker) 可以選任意顏色，等於新增 web 沒有的功能，違反 ADR-0001「web 沒有的功能不加」。這是刻意不採用 HIG 建議，要寫進 DESIGN.md 或 parity.md。

## 13. 空白列與長字串（機器人記帳，發現 11）

**原文依據**

> Group related items to clearly express related information or functions. For example, you might use negative space, container shapes, or separator lines to show which elements are related and which are unrelated.（[Layout › Visual hierarchy](https://developer.apple.com/design/human-interface-guidelines/layout#Visual-hierarchy)）

> Make useful label text selectable. If a label contains useful information — like an error message, a location, or an IP address — consider letting people select and copy it for pasting elsewhere.（[Labels › Best practices](https://developer.apple.com/design/human-interface-guidelines/labels#Best-practices)）

**中文重點**

- 【建議】容器形狀和分隔線是在表達「這些東西彼此相關」（[Layout](https://developer.apple.com/design/human-interface-guidelines/layout#Visual-hierarchy)）。【推論】空白列是一個沒有內容的容器，會讓人以為少了什麼。
- 【建議】有用的文字要讓人能選取、複製（[Labels](https://developer.apple.com/design/human-interface-guidelines/labels#Best-practices)）；長字串可以從中間截斷，保留頭尾（[Lists and tables › Content](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#Content)）。

**對本 app 的建議（【推論】）**

- **空白列的可能原因**：`BotScreen.swift` 的 `pairingSection` 把 `if let code = model.visiblePairingCode` 放在 `TimelineView` 裡面。沒有驗證碼時，`TimelineView` 仍然是 `Section` 的一個子 view，推測 `List` 替它建了一列空白。這一點沒有查到文件說明，需要實測。
- **空白列的改法**：「有沒有驗證碼」要在列的層級判斷；倒數歸零時顯示「已過期」文字，不要回傳空內容。
- **Webhook 網址**：改成一行、`truncationMode(.middle)`，保留開頭的網域和結尾的路徑；旁邊或下一列放「複製網址」按鈕，沿用綁定指令複製按鈕的樣式。XXL 時中間截斷後可能只剩幾個字元，所以複製按鈕才是主要的取得方式。

## SwiftUI API 對照表

最低版本取自 DocC JSON 的 `introducedAt`（iOS）。本 app 最低 iOS 26.0，下表全部可以直接使用。

| API | 最低 iOS | 官方文件 | 用途（章節） |
|---|---|---|---|
| `ViewThatFits` | 16.0 | [連結](https://developer.apple.com/documentation/swiftui/viewthatfits) | 依空間在一行和堆疊（或捲動）之間切換（§2、§12） |
| `AnyLayout`／`HStackLayout`／`VStackLayout` | 16.0 | [連結](https://developer.apple.com/documentation/swiftui/anylayout) | 切換版面方向，同時保留子 view 狀態（§2） |
| `DynamicTypeSize`、`.isAccessibilitySize` | 15.0 | [連結](https://developer.apple.com/documentation/swiftui/dynamictypesize) | 判斷字級；xxLarge 不是 accessibility 尺寸（§2） |
| `lineLimit(_:)`（`Int?`） | 13.0 | [連結](https://developer.apple.com/documentation/swiftui/view/linelimit(_:)-513mb) | 限制列內每個 `Text` 的行數（§1） |
| `truncationMode(_:)` | 13.0 | [連結](https://developer.apple.com/documentation/swiftui/view/truncationmode(_:)) | 從開頭、中間或結尾截斷（§1、§13） |
| `minimumScaleFactor(_:)` | 13.0 | [連結](https://developer.apple.com/documentation/swiftui/view/minimumscalefactor(_:)) | 金額縮小以維持單行（§2） |
| `LabeledContent` | 16.0 | [連結](https://developer.apple.com/documentation/swiftui/labeledcontent) | 一個欄位一列、欄位標籤、導覽列的摘要值（§3、§4、§7） |
| `NavigationLink(value:)`＋`navigationDestination(for:destination:)` | 13.0／16.0 | [連結](https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:)) | 精簡列 push 到信用卡詳細頁（§4） |
| `DisclosureGroup` | 14.0 | [連結](https://developer.apple.com/documentation/swiftui/disclosuregroup) | 收合公式明細（§3） |
| `swipeActions(edge:allowsFullSwipe:content:)` | 15.0 | [連結](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:)) | 列上的捷徑動作（§5） |
| `contextMenu(menuItems:)` | 13.0 | [連結](https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:)) | 長按選單（§5） |
| `Menu` | 14.0 | [連結](https://developer.apple.com/documentation/swiftui/menu) | 「繳款」「新增預算額度」pull-down；選單項目副標題（§5、§8） |
| `Picker(selection:content:label:currentValueLabel:)` | 18.0 | [連結](https://developer.apple.com/documentation/swiftui/picker/init(selection:content:label:currentvaluelabel:)) | 詳細的選項搭配精簡的選擇值（§8） |
| `PickerStyle.menu`／`.navigationLink`／`.segmented` | 14.0／16.0／13.0 | [menu](https://developer.apple.com/documentation/swiftui/pickerstyle/menu)、[navigationLink](https://developer.apple.com/documentation/swiftui/pickerstyle/navigationlink)、[segmented](https://developer.apple.com/documentation/swiftui/pickerstyle/segmented) | 篩選 sheet 和表單的選擇器（§6、§8） |
| `DatePicker`（`in:` 範圍） | 13.0 | [連結](https://developer.apple.com/documentation/swiftui/datepicker) | 起日、迄日（§6） |
| `TextField(text:prompt:label:)` | 15.0 | [連結](https://developer.apple.com/documentation/swiftui/textfield/init(text:prompt:label:)) | prompt 當 placeholder（§7） |
| `sheet(isPresented:onDismiss:content:)` | 13.0 | [連結](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)) | 篩選 sheet（§6） |
| `presentationDetents(_:)`、`presentationDragIndicator(_:)` | 16.0 | [detents](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:))、[grabber](https://developer.apple.com/documentation/swiftui/view/presentationdragindicator(_:)) | medium／large 高度與 grabber（§6） |
| `navigationSubtitle(_:)` | **26.0** | [連結](https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:)) | 顯示目前的篩選範圍（§6） |
| `ToolbarItem` | 14.0 | [連結](https://developer.apple.com/documentation/swiftui/toolbaritem) | 篩選按鈕、「編輯」（§4、§6） |
| `.bordered`／`.borderedProminent` | 15.0 | [bordered](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/bordered)、[borderedProminent](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/borderedprominent) | 停用時保留按鈕外形（§9） |
| `disabled(_:)` | 13.0 | [連結](https://developer.apple.com/documentation/swiftui/view/disabled(_:)) | 條件停用（§9） |
| `ScrollView(.horizontal)` | 13.0 | [連結](https://developer.apple.com/documentation/swiftui/scrollview) | 色塊橫向捲動（§12） |
| `scrollPosition(id:anchor:)`、`scrollTargetLayout()` | 17.0 | [position](https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:))、[layout](https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:)) | 捲到已選的顏色（§12） |
| `contentMargins(_:_:for:)` | 17.0 | [連結](https://developer.apple.com/documentation/swiftui/view/contentmargins(_:_:for:)) | 露出部分色塊，提示可以捲動（§12） |
| `ColorPicker` | 14.0 | [連結](https://developer.apple.com/documentation/swiftui/colorpicker) | 評估後不採用（§12） |
| `accessibilityElement(children:)` | 13.0 | [連結](https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:)) | 去掉前綴後，由 VoiceOver 念回（§1） |
| `Gauge`／`ProgressView` | 16.0／14.0 | [Gauge](https://developer.apple.com/documentation/swiftui/gauge)、[ProgressView](https://developer.apple.com/documentation/swiftui/progressview) | 儲蓄目標的進度（§1） |
| `SectorMark` | 17.0 | [連結](https://developer.apple.com/documentation/charts/sectormark) | 甜甜圈圖，5～7 塊以內（§10） |
| `foregroundStyle(by:)`、`chartForegroundStyleScale(domain:range:type:)`、`chartLegend(_:)` | 16.0 | [by](https://developer.apple.com/documentation/charts/chartcontent/foregroundstyle(by:))、[scale](https://developer.apple.com/documentation/swiftui/view/chartforegroundstylescale(domain:range:type:))、[legend](https://developer.apple.com/documentation/swiftui/view/chartlegend(_:)) | 圖表和清單共用顏色對照、圖例（§10） |
| `Date.FormatStyle`、`formatted(date:time:)` | 15.0 | [FormatStyle](https://developer.apple.com/documentation/foundation/date/formatstyle)、[formatted](https://developer.apple.com/documentation/foundation/date/formatted(date:time:)) | 依 locale 格式化日期（§11） |

## 未查證或不確定的項目

1. ~~**巡覽的「XXL」對應哪個 content size category**~~：已確認。巡覽傳的是 `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryXXL`，也就是 `DynamicTypeSize.xxLarge`（[UIContentSizeCategory.extraExtraLarge](https://developer.apple.com/documentation/uikit/uicontentsizecategory/extraextralarge)），不是 accessibility 尺寸，§2 的結論成立。另外補拍了 `UICTContentSizeCategoryAccessibilityXXXL`（AX5）。
2. **SwiftUI `Text` 能不能讓中文依詞斷行**（避免從詞中間斷開）：沒有找到 Apple 文件。
3. **`LabeledContent` 在 accessibility 字級會不會自動改成上下排列**：文件沒有說明。【推論·實測】AX5（`UICTContentSizeCategoryAccessibilityXXXL`）截圖中，統計頁用 `LabeledContent` 的分類列自動改成 label 在上、金額在下；同一輪裡用 `HStack` 自排的週期收支列，金額被拆成三行。只在 iPhone 17 模擬器（iOS 27.0）觀察，沒有文件保證。
4. **Picker 選項的呈現**：`.menu` 樣式的 Picker 選項，能不能像 `Menu` 的 `Button` 一樣顯示副標題；Picker 內容能不能用 `Section` 分組、`Label` 的圖示會不會顯示；文件都沒有說明。
5. **`NavigationLink` 在 `List` 裡會不會自動顯示 disclosure indicator**：本次讀的 SwiftUI 文件沒有明文寫出；HIG 的開發指引連到的是 UIKit 的 `disclosureIndicator`。
6. **`List` 會不會替內容為空的子 view 建立空白列**（例如 `TimelineView` 裡的 `if` 不成立時）：沒有找到文件，§13 是推論。
7. **後端接不接受 8 色以外的代表色、web 能不能正確顯示**：沒有查。這會影響能不能改用 `ColorPicker`；本研究依 ADR-0001 不改。
8. **`navigationSubtitle` 的長度限制、在 large title 模式下的樣子和截斷方式**：文件只寫「displayed with the navigation title in the navigation bar」。
9. **§11 的日期格式**：只在 macOS 27.0 上實測，iOS 27 實機的輸出沒有驗證。
10. **HIG 沒有「篩選 sheet」或「統計摘要卡」的專章**：§3、§6 的做法是從相鄰的指引組合推得的。
11. **Form 裡的 Picker 在大字級時把 label 擠到值的上方**：推定是系統的自動版面，沒有找到文件描述。

## 來源清單（本次實際讀取）

**HIG**（DocC JSON 全文）

- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)、[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)、[Labels](https://developer.apple.com/design/human-interface-guidelines/labels)、[Writing](https://developer.apple.com/design/human-interface-guidelines/writing)、[Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls)、[Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)、[Menus](https://developer.apple.com/design/human-interface-guidelines/menus)、[Pull-down buttons](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons)、[Pop-up buttons](https://developer.apple.com/design/human-interface-guidelines/pop-up-buttons)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)、[Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)
- [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)、[Modality](https://developer.apple.com/design/human-interface-guidelines/modality)、[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)、[Icons](https://developer.apple.com/design/human-interface-guidelines/icons)、[Searching](https://developer.apple.com/design/human-interface-guidelines/searching)、[Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields)、[Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data)、[Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers)、[Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Color wells](https://developer.apple.com/design/human-interface-guidelines/color-wells)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)、[Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views)、[Collections](https://developer.apple.com/design/human-interface-guidelines/collections)、[Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures)
- [Charts](https://developer.apple.com/design/human-interface-guidelines/charts)、[Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)、[Gauges](https://developer.apple.com/design/human-interface-guidelines/gauges)、[Progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators)

**Developer Documentation**（DocC JSON 全文）

- SwiftUI 版面：[ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits)、[AnyLayout](https://developer.apple.com/documentation/swiftui/anylayout)、[DynamicTypeSize](https://developer.apple.com/documentation/swiftui/dynamictypesize)、[isAccessibilitySize](https://developer.apple.com/documentation/swiftui/dynamictypesize/isaccessibilitysize)、[dynamicTypeSize(_:)](https://developer.apple.com/documentation/swiftui/view/dynamictypesize(_:))、[lineLimit(_:)](https://developer.apple.com/documentation/swiftui/view/linelimit(_:)-513mb)、[truncationMode(_:)](https://developer.apple.com/documentation/swiftui/view/truncationmode(_:))、[Text.TruncationMode](https://developer.apple.com/documentation/swiftui/text/truncationmode)、[minimumScaleFactor(_:)](https://developer.apple.com/documentation/swiftui/view/minimumscalefactor(_:))、[textSelection(_:)](https://developer.apple.com/documentation/swiftui/view/textselection(_:))、[accessibilityElement(children:)](https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:))
- SwiftUI 列表與導覽：[LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent)、[NavigationLink](https://developer.apple.com/documentation/swiftui/navigationlink)、[navigationDestination(for:destination:)](https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:))、[DisclosureGroup](https://developer.apple.com/documentation/swiftui/disclosuregroup)、[swipeActions](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:))、[contextMenu(menuItems:)](https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:))、[Menu](https://developer.apple.com/documentation/swiftui/menu)、[List](https://developer.apple.com/documentation/swiftui/list)
- SwiftUI 輸入與 sheet：[Picker](https://developer.apple.com/documentation/swiftui/picker)、[init(selection:content:label:currentValueLabel:)](https://developer.apple.com/documentation/swiftui/picker/init(selection:content:label:currentvaluelabel:))、[PickerStyle.menu](https://developer.apple.com/documentation/swiftui/pickerstyle/menu)、[PickerStyle.navigationLink](https://developer.apple.com/documentation/swiftui/pickerstyle/navigationlink)、[PickerStyle.segmented](https://developer.apple.com/documentation/swiftui/pickerstyle/segmented)、[MenuPickerStyle](https://developer.apple.com/documentation/swiftui/menupickerstyle)、[DatePicker](https://developer.apple.com/documentation/swiftui/datepicker)、[TextField](https://developer.apple.com/documentation/swiftui/textfield)、[init(text:prompt:label:)](https://developer.apple.com/documentation/swiftui/textfield/init(text:prompt:label:))、[ColorPicker](https://developer.apple.com/documentation/swiftui/colorpicker)、[sheet(isPresented:onDismiss:content:)](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:))、[presentationDetents(_:)](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:))、[presentationDragIndicator(_:)](https://developer.apple.com/documentation/swiftui/view/presentationdragindicator(_:))、[navigationSubtitle(_:)](https://developer.apple.com/documentation/swiftui/view/navigationsubtitle(_:))、[ToolbarItem](https://developer.apple.com/documentation/swiftui/toolbaritem)、[bordered](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/bordered)、[borderedProminent](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/borderedprominent)、[disabled(_:)](https://developer.apple.com/documentation/swiftui/view/disabled(_:))
- SwiftUI 捲動與進度：[ScrollView](https://developer.apple.com/documentation/swiftui/scrollview)、[scrollPosition(id:anchor:)](https://developer.apple.com/documentation/swiftui/view/scrollposition(id:anchor:))、[scrollTargetLayout(isEnabled:)](https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:))、[scrollTargetBehavior(_:)](https://developer.apple.com/documentation/swiftui/view/scrolltargetbehavior(_:))、[contentMargins(_:_:for:)](https://developer.apple.com/documentation/swiftui/view/contentmargins(_:_:for:))、[Gauge](https://developer.apple.com/documentation/swiftui/gauge)、[ProgressView](https://developer.apple.com/documentation/swiftui/progressview)
- Swift Charts：[SectorMark](https://developer.apple.com/documentation/charts/sectormark)、[foregroundStyle(by:)](https://developer.apple.com/documentation/charts/chartcontent/foregroundstyle(by:))、[chartForegroundStyleScale(_:)](https://developer.apple.com/documentation/swiftui/view/chartforegroundstylescale(_:))、[chartForegroundStyleScale(domain:range:type:)](https://developer.apple.com/documentation/swiftui/view/chartforegroundstylescale(domain:range:type:))、[chartLegend(_:)](https://developer.apple.com/documentation/swiftui/view/chartlegend(_:))、[Creating a chart using Swift Charts](https://developer.apple.com/documentation/charts/creating-a-chart-using-swift-charts)
- Foundation 與 UIKit：[Date.FormatStyle](https://developer.apple.com/documentation/foundation/date/formatstyle)、[Date.FormatStyle init(date:time:locale:calendar:timeZone:capitalizationContext:)](https://developer.apple.com/documentation/foundation/date/formatstyle/init(date:time:locale:calendar:timezone:capitalizationcontext:))、[formatted(date:time:)](https://developer.apple.com/documentation/foundation/date/formatted(date:time:))、[DateStyle.numeric](https://developer.apple.com/documentation/foundation/date/formatstyle/datestyle/numeric)、[DateStyle.abbreviated](https://developer.apple.com/documentation/foundation/date/formatstyle/datestyle/abbreviated)、[UIContentSizeCategory.extraExtraLarge](https://developer.apple.com/documentation/uikit/uicontentsizecategory/extraextralarge)
