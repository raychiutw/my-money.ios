# Apple HIG：詳細頁主要動作、有後果的次要動作、變動長度列表列（issue #248）

查核日期：2026-10-11（Asia/Taipei）

前置研究：[2026-09-29-apple-hig-layout-review.md](2026-09-29-apple-hig-layout-review.md)（列表精簡、大字級、`ViewThatFits`）、[2026-09-28-apple-hig-ios-app.md](2026-09-28-apple-hig-ios-app.md)（通則）。已寫過的只連回去，本文補 #248 專屬的四個問題。

## 研究問題與方法

**問題**：issue #248 對家庭頁與成員詳細頁有一份預設做法：(1)「報銷沖帳」放詳細頁 toolbar trailing；(2)「離開家庭」放自己的成員詳細頁；(3) 記帳列在變動長度資料下維持一致的列結構。本研究只查證，不預設答案。

- (a) 導覽堆疊詳細頁的主要動作放 toolbar 還是頁面內容？
- (b) 次要、有後果、不常用的動作（離開家庭、停止共享、登出）放哪個層級？Apple 自家 app 怎麼放？
- (c) 列表列在變動長度資料下的結構；SwiftUI `Text` 斷行行為。
- (d) toolbar 文字按鈕 vs 符號按鈕；Liquid Glass 下 `.prominent` 與單一 primary action。

**方法**

- 只採用 Apple HIG、Apple Developer Documentation 與（僅 (b) 的對照）support.apple.com 官方支援文件。HIG 是 JavaScript 渲染，所以抓 DocC JSON（`/tutorials/data/design/human-interface-guidelines/<slug>.json`、`/tutorials/data/documentation/<path>.json`）攤平後搜尋。API 版本取自 JSON 的 `metadata.platforms[].introducedAt`。support.apple.com 用 curl 抓 HTML 後去標籤讀全文（舊 `HT201081` 會 301 到 `102652`）。
- 標記沿用前案：**【規定·技術】** Apple 文件寫明的系統行為／API；**【建議】** HIG best practice；**【推論】** 套用到本 app 的工程判斷，非 Apple 原文；**未查證** 找不到原文，不編造。
- 唯一的本機實測是 §(c) 的斷行實驗：macOS 27.0 上用 CoreText（`CTTypesetterSuggestLineBreak`）。它是 SwiftUI `Text` 底下同一系的文字排版，但**不等於** iOS 上的 SwiftUI `Text`，所以 iOS 側標**未實測**（本機沒有可用的 iOS 模擬器）。歸類為【推論】。
- 讀 HIG 時發現一個陷阱：Buttons 頁的「Use toolbar buttons to provide … contextual actions」「Prefer buttons that span the width of the screen for primary actions」在 DocC 結構中屬於 **watchOS** 小節，不是 iOS。本文不引用它們來支持 iPhone 做法。

## 結論摘要

1. **(a) 詳細頁主要動作**：HIG 沒有一條直接回答「詳細頁的主要動作放 toolbar 還是內容」。【建議】toolbar 放「支援主要任務、最常用」的動作，且只指定一個 primary action、放 trailing（[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)）；【推論】「對這位成員沖帳」是此頁的核心任務，放 toolbar trailing 合規，但文字標題（「報銷沖帳」）受「優先用符號、edit 這類難以符號表達的才用文字」限制，需要先決定用文字或符號；另一個同樣合規的選項是放內容區（見 (a) 結論）。
2. **(b) 次要有後果動作**：【建議】HIG 對破壞性動作的規定集中在「用 destructive role、要確認、不要設為 primary」，**沒有**規定放哪一頁。【推論】Apple 自家「家人共享」把「Stop Using Family Sharing」放在**自己的成員詳細頁**（點自己的名字進去），「新增成員」放家庭主畫面 toolbar 的 Add Member 按鈕，這與預設做法一致；但那是 Settings app 的做法，不是 HIG 條文。
3. **(c) 變動長度列**：【建議】列文字精簡、截斷降到最少、大字級改堆疊（[Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)、[Typography](https://developer.apple.com/design/human-interface-guidelines/typography#Supporting-Dynamic-Type)、[Layout](https://developer.apple.com/design/human-interface-guidelines/layout#Best-practices)）。HIG **沒有**「同一列表內有的列兩欄、有的列堆疊」的條文；【推論】這是依空間決定的列內重排，可以做，但要以同一組資訊階層為前提。中文在 CJK 字元之間任一處都可斷行，`・` 與 U+2060 擋不住字間斷行（本機 CoreText 實測）。
4. **(d) toolbar 文字 vs 符號**：【建議】預設用符號、edit 這類才用文字；`.prominent` 只給一個 primary action 且放 trailing；不要在共用背景的項目混用文字與符號。

---

## (a) 詳細頁的主要動作：toolbar 還是內容底部

### 原文依據

**Toolbars 頁**（[連結](https://developer.apple.com/design/human-interface-guidelines/toolbars)）：

- 【建議】定義：「Toolbars act on content in the view, facilitate navigation, and help orient people in the app.」三種內容：view 標題、導覽控制項、「Actions, or bar items, like buttons and menus」。
- 【建議】「Provide actions that support the main tasks people perform. In general, prioritize the commands that people are most likely to want.」
- 【建議】「Choose items deliberately to avoid overcrowding.」「you don't want to put too many items in the toolbar」。
- 【建議】「Use the .prominent style for key actions such as Done or Submit. This separates and tints the action so there's a clear focal point. Only specify one primary action, and put it on the trailing side of the toolbar.」
- 【建議】Trailing edge 的定位：「The trailing edge contains important items that need to remain available … It also includes a primary action like Done when one exists.」（同頁「Placement」小節；該小節在 DocC 中涵蓋 iPad／Mac 視窗，但 iPhone navigation bar 的 trailing 位置由下面的 API 文件確認。）

**ToolbarItemPlacement.primaryAction**（[連結](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/primaryaction)，iOS 14.0+）：

- 【規定·技術】「A primary action is a more frequently used action for the current context.」
- 【規定·技術】「In iOS, iPadOS, and tvOS, the location for the primary action is the trailing edge of the navigation bar.」

**ToolbarItemPlacement.confirmationAction**（[連結](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/confirmationaction)）：

- 【規定·技術】「Use confirmation actions to receive user confirmation of a particular action.」「In iOS, iPadOS, and tvOS, the system places confirmationAction items in the same location as a primaryAction placement.」這是給 **modal 介面**用的（abstract：「A placement for confirmation actions in a modal interface」），詳細頁（push）不是 modal。

**Buttons 頁**（[連結](https://developer.apple.com/design/human-interface-guidelines/buttons#Style)）：

- 【建議】「use a button that has a prominent visual style for the most likely action in a view … Keep the number of prominent buttons to one or two per view. Presenting too many prominent buttons increases cognitive load」。
- 【建議】「Use style — not size — to visually distinguish the preferred choice among multiple options.」

### 中文重點

- **數量限制有兩條，口徑不同**：toolbar 內的 `.prominent` primary action 是「只指定一個」；整個畫面（含內容區按鈕）的 prominent 按鈕是「一到兩個」。兩者合計時，toolbar 放了 prominent 的 primary action，內容區就不宜再放另一顆搶眼的實心按鈕（這是【推論】，原文沒有把兩條合併）。
- HIG **沒有**寫「push 進來的詳細頁，主要動作該放 toolbar 還是內容底部」。**未查證**這個具體命題。Apple 文件寫明的只有：navigation bar 的 trailing edge 是 primary action 的家（API 文件）、toolbar 放「支援主要任務、最常用」的動作（HIG）。
- `.prominent`／primary action 的範例都是 Done、Submit，也就是**確認一項編輯／送出**，語意偏 modal 表單。「對一位成員報銷沖帳」是「對這份資料做一個有結果的動作」，不是確認編輯。HIG 沒有禁止，但也沒有直接背書。

### 結論與對本 app 的建議【推論】

- 以 HIG 為依據，**兩種放法都不違規**：
  1. toolbar trailing（`ToolbarItem(placement: .primaryAction)`）：符合「支援主要任務」「primary action 在 trailing」；缺點是詳細頁內容很長時，動作離資料遠，且 (d) 的文字／符號問題要解。
  2. 頁面內容中、緊接在「待報銷金額」那個 section 下方的 prominent 按鈕：符合 Buttons「最可能的動作用 prominent 樣式」，動作與它所作用的資料相鄰，也不受「toolbar 優先用符號」影響。
- 若走 toolbar：只放這**一個** `.prominent` 動作；其他（例如編輯、更多）用符號或收進 More menu，且不在同一個共用背景裡混放文字與符號（見 (d)）。
- 原預設（放 toolbar trailing）**沒有被推翻**，但 HIG 沒有把它列為唯一或更好的做法；決策要建立在「這個動作是否是此頁的唯一主要任務」與「文字標題能否放得下」，不是在 HIG 條文。

---

## (b) 次要、有後果、不常用的動作放在哪個層級

### 原文依據：HIG

**Buttons**（[Role](https://developer.apple.com/design/human-interface-guidelines/buttons#Role)）：

- 【建議】三種 role 之一：「Destructive. The button performs an action that can result in data destruction.」
- 【建議】「a primary button uses an app's accent color, whereas a destructive button uses the system red color.」
- 【建議】「Don't assign the primary role to a button that performs a destructive action, even if that action is the most likely choice. Because of its visual prominence, people sometimes choose a primary button without reading it first.」

**Alerts**（[連結](https://developer.apple.com/design/human-interface-guidelines/alerts)）：

- 【建議】「Avoid displaying alerts for common, undoable actions, even when they're destructive … In comparison, when people take an uncommon destructive action that they can't undo, it's important to display an alert in case they initiated the action accidentally.」
- 【建議】「Use the destructive style to identify a button that performs a destructive action people didn't deliberately choose.」（例：刻意選了 Empty Trash 之後的確認 alert，該按鈕不用 destructive 樣式。）
- 【建議】「If there's a destructive action, include a Cancel button … Always use the title 'Cancel'」；「Avoid using OK as the default button title unless the alert is purely informational … A specific button title like 'Erase,' 'Convert,' 'Clear,' or 'Delete' helps people understand the action they're taking.」
- 【建議】「Use an action sheet — not an alert — to offer choices related to an intentional action.」

**Action sheets**（[連結](https://developer.apple.com/design/human-interface-guidelines/action-sheets)）：

- 【建議】SwiftUI 以 confirmation dialog 呈現：「When you use SwiftUI, you can offer action sheet functionality in all platforms by specifying a view-presentation for a confirmation dialog.」
- 【建議】「Use action sheets sparingly … they interrupt the current task」；「If necessary, provide a Cancel button that lets people reject an action that might destroy data. Place the Cancel button at the bottom」；「A SwiftUI confirmation dialog includes a Cancel button by default.」
- 【建議】「Make destructive choices visually prominent. Use the destructive style for buttons that perform destructive actions, and place these buttons at the top of the action sheet」。
- 【建議】「Avoid displaying more than four buttons in an action sheet, including the Cancel button.」

**Pull-down buttons**（[連結](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons)）：

- 【建議】「Let people know when a pull-down button's menu item is destructive, and ask them to confirm their intent. Menus use red text to highlight actions that you identify as potentially destructive. When people choose a destructive action, the system displays an action sheet (iOS) or popover (iPadOS) in which they can confirm」（原文為 action-sheets／popovers 連結，上為攤平文字）。
- 【建議】「Avoid putting all of a view's actions in one pull-down button. A view's primary actions need to be easily discoverable」。

**Modality**（[連結](https://developer.apple.com/design/human-interface-guidelines/modality)）：

- 【建議】「When necessary, help people avoid data loss by getting confirmation before closing a modal view.」（針對關閉 modal 時的資料遺失，與離開家庭不是同一件事。）

**Settings**（[連結](https://developer.apple.com/design/human-interface-guidelines/settings)）：

- 【建議】「Put general, infrequently changed settings in your custom settings area … both apps and games might offer options related to people's accounts.」把「不常改、與帳號有關」的選項放進 settings 區域；【推論】這支持「不常用的帳號／群組類動作不要放在日常畫面的搶眼位置」，但原文講的是設定項，不是破壞性動作。

**Managing accounts**（[連結](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)）：

- 【建議】「If you help people create an account within your app or game, you must also help them delete it, not just deactivate it.」
- 登出的那條（「Avoid displaying a sign-out option when people are signed in at the system level」）屬於 **TV provider** 的情境，不適用 iPhone app。**未查證**：HIG 沒有 iOS 登出按鈕「放哪」的原文。

### 原文依據：Apple 自家 app（僅 support.apple.com）

來源：[How to leave or remove a member from a Family Sharing group](https://support.apple.com/en-us/102652)（舊編號 HT201081）、[How to set up Family Sharing on your iPhone, iPad, or Mac](https://support.apple.com/en-us/108380)。2026-10-11 實際抓取。

- **離開（成員自己）**：「Any adult can remove themselves from a Family Sharing group.」iPhone：「Open the Settings app, then tap Family. If you don't see Family, tap your name, then tap Family. Tap your name, then tap Stop Using Family Sharing.」→ 路徑是 Family 主畫面 → **點自己的名字**（自己的成員詳細頁）→ Stop Using Family Sharing。
- **停止／解散（organizer）**：「On the Family Sharing organizer's iPhone or iPad: Open the Settings app, then tap Family. Tap your name, then tap Stop Using Family Sharing.」同樣在 organizer 自己的成員頁；文中說明「When you disband a family group, everyone loses access to shared purchases and services.」
- **移除別人（organizer）**：「Tap the name of the family member that you want to remove. Tap Remove [name] from Sharing Group.」→ 對方的成員詳細頁。
- **新增成員／邀請**：「Open the Settings app, then tap Family. Tap the Add Member button. Tap Invite Others …」→ 家庭主畫面上的 **Add Member 按鈕**（文中以按鈕圖示描述；原文沒說它在 navigation bar 還是列表內，所以「是否在 toolbar」**未查證**。）
- 確認 UI 的外觀（是否 alert、action sheet）在這些文章**沒有描述**，未查證。

### 中文重點

- HIG 對「有後果的動作」說了五件事：用 destructive role／紅色；不要設為 primary；要確認並有 Cancel；確認用 action sheet（confirmation dialog）而非 alert 時要提供選項，只要確認不可逆動作則 alert 可以；不常見且不可復原的動作才值得確認。**沒有一條規定放哪個畫面、離入口多遠。**
- 「不要太顯眼」的依據是間接的：Buttons 說 prominence 讓人不讀就按，所以破壞性動作不給 primary；Settings 說不常改的選項放進設定區。兩者都不是「把破壞性動作藏深一點」的明文。
- Apple 自家做法（官方支援文件）：**離開／停止共享在「自己的成員詳細頁」，不在家庭主畫面**；移除他人在「對方的成員詳細頁」；新增成員是家庭主畫面上的按鈕。

### 結論與對本 app 的建議【推論】

- 「離開家庭群組」放自己的成員詳細頁，**與 Apple 自家 Family Sharing 路徑一致**，也不違反 HIG；預設做法**成立**。這是以 Apple 官方支援文件佐證，不是 HIG 條文。
- 具體做法：在詳細頁內容底部，單獨一個 `Section` 放 `Button(role: .destructive)`（不是 `.prominent`、不是 toolbar 上的 primary），點了出 `confirmationDialog`（destructive 按鈕在最上、系統自動附 Cancel）。按鈕標題用具體動詞（「離開家庭」），不用「確定」。「停止共享」若是只有 organizer 才有，同理放 organizer 自己的成員頁。
- 登出：**未查證**放哪；本 app 若已有設定頁，沿用「不常改、與帳號有關的選項放設定區」的 Settings 條文即可，仍用 destructive role 與確認。
- 新增成員／邀請：Apple 自家是家庭主畫面上的 Add Member 按鈕；本 app 放家庭頁 toolbar 的符號按鈕（`person.badge.plus`）是合理對映，【推論】，非條文。

---

## (c) 變動長度資料下的列表列結構

### 原文依據

**Lists and tables**（[Content](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables#Content)）：

- 【建議】「Keep item text succinct so row content is comfortable to read. Short, succinct text can help minimize truncation and wrapping, making text easier to read and scan.」
- 【建議】「If each item consists of a large amount of text, consider alternatives that help you avoid displaying over-large table rows. For example, you could list item titles only, letting people choose an item to reveal its content in a detail view.」
- 【建議】「Consider ways to preserve readability of text that might otherwise get clipped or truncated … Sometimes, an ellipsis in the middle of text can make an item easier to distinguish because it preserves both the beginning and the end of the content.」
- 【建議】「Choose a row style that fits the information you need to display.」（舉例：前端小圖＋簡短標籤；內建 row style 可用。）
- 【建議】「Use an info button only to reveal more information about a row's content … If you need to let people drill into a list or table row's subviews, use a disclosure indicator accessory control.」（與 #246 家庭頁成員列有 disclosure indicator 的做法一致。）

**Typography › Supporting Dynamic Type**（[連結](https://developer.apple.com/design/human-interface-guidelines/typography#Supporting-Dynamic-Type)）：

- 【建議】「Make sure your app's layout adapts to all font sizes.」
- 【建議】「Keep text truncation to a minimum as font size increases. In general, aim to display as much useful text at the largest accessibility font size as you do at the largest standard font size. Avoid truncating text in scrollable regions unless people can open a separate view to read the rest of the content.」
- 【建議】「Consider adjusting your layout at large font sizes. When font size increases in a horizontally constrained context, inline items (like glyphs and timestamps) and container boundaries can crowd text and cause truncation or overlapping. To improve readability, consider using a stacked layout where text appears above secondary items. Multicolumn text can also be less readable at large sizes … Reduce the number of columns when the font size increases」
- 【建議】「Maintain a consistent information hierarchy regardless of the current font size. For example, keep primary elements toward the top of a view even when the font size is very large」。

**Layout › Best practices**（[連結](https://developer.apple.com/design/human-interface-guidelines/layout#Best-practices)）：

- 【建議】「Be prepared for text-size changes … horizontally adjacent views may need to stack vertically to provide more space for text; table rows or other containers may need to grow in height so that text isn't cropped or doesn't overlap other content; and table rows with a single line of text by default might need to grow vertically to accommodate multiple lines of text.」
- 【建議】「Preview your app on multiple devices, using different size classes, localizations, and text sizes.」
- 【建議】「Use consistent spacing. When content isn't consistently spaced, it no longer looks like a grid and it's harder for people to scan.」

**SwiftUI 側（Apple 文件）**：

- 【規定·技術】`ViewThatFits`（[連結](https://developer.apple.com/documentation/swiftui/viewthatfits)，iOS 16.0+）：「evaluates its child views in the order you provide them to the initializer. It selects the first child whose ideal size on the constrained axes fits within the proposed size … By default, ViewThatFits constrains in both the horizontal and vertical axes.」重點：判斷用的是各子 view 的 **ideal size**；`Text` 沒有 `fixedSize` 時，ideal size 是不折行的單行寬度。
- 【規定·技術】`Text`（[連結](https://developer.apple.com/documentation/swiftui/text)）：「If the view accepts the proposal but the text doesn't fit into the available space, the view uses a combination of wrapping, tightening, scaling, and truncation to make it fit.」可用 `lineLimit(_:)`、`allowsTightening(_:)`、`minimumScaleFactor(_:)`、`truncationMode(_:)` 設定。
- 【規定·技術】`fixedSize()`（[連結](https://developer.apple.com/documentation/swiftui/view/fixedsize())，iOS 13.0+）：「maintains the ideal size of its children … This can result in the view exceeding the parent's bounds」。`fixedSize(horizontal:vertical:)` 可只固定一個軸；【推論】`Text(...).fixedSize(horizontal: false, vertical: true)` 是「寬度跟隨、高度完整顯示」的慣用寫法，用來避免被截成一行。
- 【規定·技術】`lineLimit(_:reservesSpace:)`（iOS 16.0+）：「When the text occupies more space than the provided limit, a Text view truncates its content」。
- 【規定·技術】`truncationMode(_:)`：可選 head／middle／tail，截斷處加 ellipsis。
- 【規定·技術】UIKit／AppKit 的 `NSParagraphStyle.lineBreakStrategy`（[連結](https://developer.apple.com/documentation/uikit/nsparagraphstyle/linebreakstrategy-swift.property)）：「Line-break strategies are collections of options the system uses to determine where to break lines in a paragraph. This is different from lineBreakMode …」預設 `NSLineBreakStrategyNone`。**未查證**：在 SwiftUI 的 `View`／`Text` 索引（`swiftui/view`、`swiftui/text`）中**查不到**對應的公開修飾器，所以 SwiftUI 側沒有 Apple 文件寫明的、可直接調整 `lineBreakStrategy` 的方法。
- 【規定·技術】`Text` 沒有「某段文字不可從中間斷」的公開 API；Apple 文件沒有對 NBSP 或 U+2060 在 SwiftUI `Text` 的行為做說明。**未查證**（見下方實測，僅限 CoreText）。

### 本機實測（macOS 27.0、CoreText；SwiftUI `Text`／iOS 未實測）【推論】

方法：`CTTypesetterSuggestLineBreak`，PingFangTC 17 pt，字串「待報銷 $1,200・已沖帳 $300・共 3 筆」在 120／170／230 pt 寬度下的斷行（`[ ]` 為一行）。

| 變體 | 120 pt | 230 pt |
|---|---|---|
| 原文 | `[待報銷 ][$1,200・已沖][帳 $300・共 3 ][筆]` | `[待報銷 $1,200・已沖帳 ][$300・共 3 筆]` |
| `・` 前後加 U+2060 | `[待報銷 ][$1,200⁠・⁠已沖][帳 $300⁠・⁠共 3 ][筆]` | `[待報銷 $1,200⁠・⁠已沖帳 ][$300⁠・⁠共 3 筆]` |
| 空格改 NBSP（U+00A0） | `[待報][銷 $1,200・已][沖帳 $300・][共 3 筆]` | `[待報銷 $1,200・已沖][帳 $300・共 3 筆]` |
| 每個漢字之間插 U+2060 | `[待⁠報⁠銷⁠$1,200][・已沖帳]` | `[待⁠報⁠銷⁠$1,200・已沖帳]` |

觀察：

1. 中文在**任兩個漢字之間**都可斷行（「已沖｜帳」被從詞中間拆開），不依賴 `・`。因此「在 `・` 處斷行」不是可依賴的行為；斷點是被寬度決定的，會出現 `$1,200・已沖` 這種任意切法。
2. 在 `・` 前後加 U+2060 **沒有改變**斷點，因為斷行發生在漢字之間，不在 `・` 旁。
3. NBSP 只影響它取代的空格：數字與前後文被黏住，但漢字之間照樣可斷（還讓斷點更糟，例如「待報｜銷」）。
4. 只有在**每個**相鄰字元之間插 U+2060 才能把「待報銷」黏成一塊；這會讓字串帶隱形字元，影響複製、搜尋、VoiceOver，不是好做法。
5. 以上是 CoreText 的結果；SwiftUI `Text` 在 iOS 上是否一致，**未實測**。

### 中文重點

- 「同一列表內有的列兩欄、有的列堆疊」：HIG 沒有條文。Typography 與 Layout 的條文是**依字級與空間調整**（堆疊、減少欄數、列高變高），沒有要求同一列表所有列必須同一種排法，也沒有禁止。對「一致性」唯一的條文是「Maintain a consistent information hierarchy」（資訊階層一致，不是版型一致）與「Use consistent spacing」。
- 「列內文字精簡」的 HIG 答案是：把次要資訊移出列、放進詳細頁，不是靠折行技巧撐住。
- 「不要被從中間折斷」：HIG 沒有講；SwiftUI 官方文件也沒有可直接做這件事的 `Text` API。可操作的是**結構**：把不可分的片段做成各自獨立的 `Text`，用 `ViewThatFits` 或垂直堆疊來決定整塊放哪，而不是靠字元技巧。

### 對本 app 的建議【推論】

- 記帳列：標題＋金額為主列；次要資訊（分類、帳戶、日期）最多一行，放不下就**整段**移到第二行（堆疊），不讓它在行內自行折行。這與 HIG「stacked layout where text appears above secondary items」相符。
- 兩欄 vs 堆疊以 `ViewThatFits { HStack(…) ; VStack(…) }` 決定，每個候選項裡的 `Text` 加 `.lineLimit(1)` 與 `.fixedSize(horizontal: true, vertical: false)`（讓 ideal size 為單行寬度，否則 `ViewThatFits` 永遠選第一個）。這是【推論】：文件只說 `ViewThatFits` 看 ideal size，上面的 modifier 組合需在 iOS 模擬器／真機驗證，**未實測**。
- 同一列表內不同列落入不同分支（有的兩欄、有的堆疊）：HIG 無禁止；但為了掃讀，【推論】盡量讓「金額」永遠在同一個位置（例如 trailing 或固定在第一行），只有次要資訊在分支間移動。
- 金額、日期等「單一原子」片段：各自 `Text`，不要拼成一個長字串再靠 `・` 斷行；中文標籤（「待報銷」）用 `fixedSize` 避免被拆。不要用 U+2060／NBSP 技巧。
- 要驗證就用本 repo 的 `scripts/screen-tour.sh -s default,xxl,ax5` 檢查三種字級（HIG Layout：「Preview … using different size classes, localizations, and text sizes」）。

---

## (d) Toolbar 項目：文字 vs 符號、`.prominent` 與單一 primary action

### 原文依據

**Toolbars 頁**（[連結](https://developer.apple.com/design/human-interface-guidelines/toolbars)）：

- 【建議】「Prefer simple, recognizable symbols for items instead of text, except for actions like edit that aren't well-represented by symbols.」
- 【建議】「Prefer system-provided symbols without borders.」（toolbar 的區段本身已有視覺容器。）
- 【建議】「Use the standard Back and Close buttons … don't use a text label that says Back or Close.」
- 【建議】「Keep actions with text labels separate. Placing an action with a text label next to an action with a symbol can create the illusion of a single action with a combined text and symbol, leading to confusion and misinterpretation. If your toolbar includes multiple text-labeled buttons, the text of those buttons may appear to run together … Add separation by inserting fixed space between the buttons.」
- 【建議】「Minimize the number of groups … In general, aim for a maximum of three.」
- 【建議】「Prioritize only the most important items for inclusion in the main toolbar area … Create a More menu to include additional items.」
- 【建議】「Use the .prominent style for key actions such as Done or Submit … Only specify one primary action, and put it on the trailing side of the toolbar.」

**Adopting Liquid Glass**（[連結](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)）：

- 【建議】「Find icons to represent common actions. Consider representing common actions in toolbars with icons instead of text … For consistency, don't mix text and icons across items that share a background.」
- 【建議】「Provide an accessibility label for every icon. Regardless of what you show in the interface, always specify an accessibility label for each icon.」
- 【建議】「Determine which toolbar items to group together. Group items that perform similar actions or affect the same part of the interface」
- 【建議】「Audit toolbar customizations … your use of fixed spacers or custom items, as these can appear inconsistent with system behavior.」

**SwiftUI API**：

- 【規定·技術】`ToolbarSpacer`（[連結](https://developer.apple.com/documentation/swiftui/toolbarspacer)，iOS 26.0+）：「A space item creates visual breaks in the toolbar between items. Spacers can have a standard fixed size or be flexible」。
- 【規定·技術】`borderedProminent`（[連結](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/borderedprominent)，iOS 15.0+）與 `glassProminent`（[連結](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent)，iOS 26.0+，「A button style that applies a prominent Liquid Glass effect based on the button's context」）。兩者文件都只在 tvOS 一節說明行為差異。
- **未查證**：HIG 的 `.prominent` 對應到哪一個具體 SwiftUI API（例如 toolbar 內 `.buttonStyle(.borderedProminent)` 或 `.glassProminent`，以及 iOS 26 toolbar item 是否自動套用）。本次在 Toolbars 頁與以上 API 文件都沒找到直接對照的說明；HIG 文字是 UIKit 語彙（`UIBarButtonItem.Style.prominent`）。實作時需在 iOS 26 模擬器／真機看實際渲染。

### 中文重點

- 「文字或符號」的原文依據很明確：預設用符號；**edit 這類難以符號表達的動作可以用文字**。「報銷沖帳」不是標準動作，也沒有大家認得的單一符號；沒有符號就得用文字，這時它**不能**與其他符號項目共用背景擠在一起（要用 fixed spacer 分開，或讓它獨佔一組）。
- primary action 只能一個、放 trailing、`.prominent`；在 Liquid Glass 下 toolbar 本身就是玻璃容器，prominent 項目會被分出並著色，形成焦點。
- 無障礙：不論用符號或文字，符號項目一定要有 accessibility label。

### 對本 app 的建議【推論】

- 若「報銷沖帳」放 toolbar：文字按鈕、`.primaryAction`、`.prominent` 風格，整個 toolbar 只剩它一個 trailing 項目；其他動作（若有）收進 More menu（`Menu` ＋ `ellipsis.circle`）。不要「文字按鈕＋符號按鈕」並排共用背景。
- 若報銷沖帳的字串在 AX5 太長：toolbar 沒有 HIG 規範的縮寫規則，文字長度需實測；這是選擇放內容區的理由之一。**未實測**。
- 任何方案都需要在 iOS 26 模擬器／真機確認 `.prominent` 外觀與 AX5 的 toolbar 表現，本機目前沒有模擬器，未實測。

---

## 未查證清單

1. HIG 對「push 進來的詳細頁，主要動作放 toolbar 還是內容底部」沒有直接條文（只有 Toolbars 的 primary action／最常用動作，與 `ToolbarItemPlacement.primaryAction` 的 trailing 位置）。
2. HIG 對 iOS app 內「登出」按鈕該放哪沒有條文（Managing accounts 只有 TV provider 的登出條文，不適用）。
3. 破壞性動作「不要太顯眼」沒有明文；只有「不要設為 primary」「用 destructive role」「確認」。
4. Apple 官方支援文件沒有描述 Add Member 按鈕是在 navigation bar 還是列表內，也沒有描述 Stop Using Family Sharing 的確認 UI 形式。
5. HIG 沒有「同一列表內列的版型必須一致或可以不一致」的條文。
6. SwiftUI 側沒有找到公開的 `lineBreakStrategy` 修飾器；NBSP、U+2060 在 SwiftUI `Text` 的行為 Apple 文件未說明；CoreText 的實測**不代表** iOS SwiftUI `Text`（iOS 未實測）。
7. HIG 的 `.prominent` 與 SwiftUI `.borderedProminent`／`.glassProminent` 在 toolbar 內的對應關係；iOS 26 實際渲染未實測。
8. `ViewThatFits` ＋ `fixedSize` 的組合在本 app 記帳列的實際結果，AX5 下的 toolbar 文字按鈕寬度：未實測（無 iOS 模擬器）。

## 參考連結

HIG

- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- [Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets)
- [Pull-down buttons](https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons)
- [Modality](https://developer.apple.com/design/human-interface-guidelines/modality)
- [Settings](https://developer.apple.com/design/human-interface-guidelines/settings)
- [Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)
- [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography#Supporting-Dynamic-Type)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout#Best-practices)

Developer Documentation

- [ToolbarItemPlacement.primaryAction](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/primaryaction)
- [ToolbarItemPlacement.confirmationAction](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/confirmationaction)
- [ToolbarItemPlacement.destructiveAction](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/destructiveaction)
- [ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [borderedProminent](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/borderedprominent)、[glassProminent](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent)
- [ViewThatFits](https://developer.apple.com/documentation/swiftui/viewthatfits)
- [Text](https://developer.apple.com/documentation/swiftui/text)
- [fixedSize()](https://developer.apple.com/documentation/swiftui/view/fixedsize())
- [lineLimit(_:reservesSpace:)](https://developer.apple.com/documentation/swiftui/view/linelimit(_:reservesspace:))
- [truncationMode(_:)](https://developer.apple.com/documentation/swiftui/view/truncationmode(_:))
- [NSParagraphStyle.lineBreakStrategy](https://developer.apple.com/documentation/uikit/nsparagraphstyle/linebreakstrategy-swift.property)

Apple 官方支援文件

- [How to leave or remove a member from a Family Sharing group](https://support.apple.com/en-us/102652)
- [How to set up Family Sharing on your iPhone, iPad, or Mac](https://support.apple.com/en-us/108380)
