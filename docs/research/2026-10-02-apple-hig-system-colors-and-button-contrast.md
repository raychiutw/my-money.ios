# Apple 平台規範研究：iOS 系統色（System Blue 等）色碼與 prominent 按鈕對比

查核日期：2026-10-02（Asia/Taipei）

查核範圍：Apple Human Interface Guidelines（[Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)、[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)、[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)，另掃過 Toolbars、Tab bars、Materials、Branding）、Apple Developer Documentation（`UIColor.systemBlue`、`Color.blue`、`Color.accentColor`、`borderedProminent`、`glassProminent`、`tint(_:)`、`UIButton.Configuration`、Specifying your app's color scheme、`NSAccentColorName`、Adopting Liquid Glass）、WWDC21 與 WWDC25 session 逐字稿、[App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)（Last Updated: June 8, 2026）。對比公式的原始定義引 [W3C WCAG 2.2](https://www.w3.org/TR/WCAG22/)（不是 Apple 來源，但 HIG 的對比表明說依據它）。舊版 HIG 色值取自 Wayback Machine 對 Apple 官方頁面的存檔（唯一的非 Apple 主機，只用來還原舊值，已逐處標明）。本文件是規範研究與工程推論，**不是**對 my-money 既有程式碼或畫面的稽核，與 [2026-09-28-apple-hig-ios-app.md](2026-09-28-apple-hig-ios-app.md) §3.2 互補。

## 研究方法與規範層級

HIG 與開發者文件網頁由 JavaScript 渲染，一律改抓官方 DocC JSON（`/tutorials/data/design/human-interface-guidelines/<頁>.json`、`/tutorials/data/documentation/<路徑>.json`），以全文為準；WWDC 逐字稿讀 session 頁面的官方 transcript。**HIG 的 System colors 表現在是圖片，色值不在文字裡**：DocC JSON 的 `references[…].alt` 以 `R-0,G-136,B-255` 的格式記錄每張色票的 RGB。為確認 alt 不是敷衍，我把 12 色 × 4 欄 = 48 張色票 PNG（`/tutorials/images/com.apple.HIG/colors-unified-*@2x.png`，檔案帶 sRGB 標記）全部下載，取中心像素逐一比對，**48 張全部與 alt 文字相同**。

每條論點標示三種層級之一：

- **【規定】**：Apple 明文硬性要求（App Review Guidelines 條文，或違反即被系統拒絕的技術要求）。
- **【建議】**：HIG 與開發者文件的 best practice（prefer／avoid／make sure 等）。HIG 不是審核清單。
- **【推論】**：研究者的判斷，或本機實測。本機實測另以資料標籤區分來源：
  - **HIG 文件值**：HIG 頁面上寫的值（含 alt 與像素比對）。
  - **API 實測值**：在 Xcode 27.0（27A266a）的 iOS Simulator 上，以 iOS 26.5（23F77）與 iOS 27.0（24A434）兩個 runtime 實際解析 `UIColor`／SwiftUI `Color` 得到的值。方法見〈附錄 A〉。

本機實測的範圍有限：是 bare process（沒有 app bundle、沒有 AccentColor asset），顯式指定 `UITraitCollection`（`userInterfaceStyle` × `accessibilityContrast`）解析色值；按鈕渲染用 `ImageRenderer` 離屏繪製。只有 iOS 26.5 與 27.0，**沒有** iOS 26.0–26.4 與 iOS 18 以前的 runtime。

## 結論

**System Blue 在 iOS 26 之後的正確色碼，與你憑記憶的色碼不一致。** 你記的 #007AFF／#0A84FF／#0040DD／#409CFF 是 2025-06-09 之前的舊版 HIG 值（iOS 18 世代）。HIG 在 2025-06-09 的 change log 寫「Updated system color values」，現行值是 #0088FF／#0091FF／#1E6EF4／#5CB8FF；我在 iOS 26.5 與 iOS 27.0 的 `UIColor.systemBlue`、`Color.blue`、`Color.accentColor`（未自訂時）解析出的值**逐位元相同**，且與 HIG 文件值一致。my-money 最低 iOS 26.0，所以舊值不會出現在支援的系統上。

| 外觀 | HIG 文件值（2025-06-09 起） | API 實測值（iOS 26.5／27.0） | 你記憶的色碼（= 舊版 HIG） | 白字對比（現行值） | 黑字對比（現行值） |
|---|---|---|---|---|---|
| Default（淺色） | 0,136,255　#0088FF | 同左 | #007AFF（不一致） | **3.52:1** | 5.97:1 |
| Default（深色） | 0,145,255　#0091FF | 同左 | #0A84FF（不一致） | **3.23:1** | 6.49:1 |
| 增強對比（淺色） | 30,110,244　#1E6EF4 | 同左 | #0040DD（不一致） | 4.57:1 | 4.59:1 |
| 增強對比（深色） | 92,184,255　#5CB8FF | 同左 | #409CFF（不一致） | **2.15:1** | 9.76:1 |

來源：HIG 文件值見[Color › Specifications](https://developer.apple.com/design/human-interface-guidelines/color#Specifications)（取得於 2026-10-02）；舊值見 [Wayback 存檔](https://web.archive.org/web/20250607225441/https://developer.apple.com/design/human-interface-guidelines/color)（2025-06-07 快照，更新前一天）。你算出的 4.02／3.65／7.56／2.83 我用舊值重算完全重現（見 §3.3），代表你的算術沒錯，只是輸入是舊色碼。

**對比算式（WCAG 2.2，[W3C 定義](https://www.w3.org/TR/WCAG22/#dfn-relative-luminance)）**：

```text
c = 8bit / 255
c_lin = c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4
L = 0.2126 * R_lin + 0.7152 * G_lin + 0.0722 * B_lin
對比 = (L_亮 + 0.05) / (L_暗 + 0.05)        白 L = 1，黑 L = 0
```

以 #0088FF 為例：R = 0 → 0；G = 136/255 = 0.5333 → ((0.5333+0.055)/1.055)^2.4 = 0.246201；B = 255/255 → 1。
L = 0.7152 × 0.246201 + 0.0722 × 1 = 0.248283。白字：1.05 / 0.298283 = **3.52**；黑字：0.298283 / 0.05 = **5.97**。
其餘三個：#0091FF 的 L = 0.274708（白 1.05/0.324708 = 3.23、黑 0.324708/0.05 = 6.49）；#1E6EF4 的 L = 0.179595（白 1.05/0.229595 = 4.57、黑 0.229595/0.05 = 4.59）；#5CB8FF 的 L = 0.437763（白 1.05/0.487763 = 2.15、黑 0.487763/0.05 = 9.76）。

**其餘結論**

1. **【推論】原驗收標準「藍底白字四種外觀都 ≥ 4.5:1」在 Apple 現行系統藍上做不到。** 白字只有「淺色增強對比」過 4.5（4.57，勉強）；淺色 3.52、深色 3.23 只過 3:1；深色增強對比 2.15 連 3:1 都不過。黑字四種外觀都 ≥ 4.5，但這不是系統預設做法（見結論 3）。
2. **【建議】HIG 沒有任何地方對 prominent／filled 按鈕的文字色或對比比例下明文規定。** Buttons 頁只說 prominent 樣式「讓系統把 accent color 套在按鈕背景」；對比數字只出現在 Accessibility 頁（依 WCAG AA：≤17 pt 要 4.5:1、18 pt 要 3:1、粗體要 3:1）與 Dark Mode 頁（最低 4.5:1、自訂色爭取 7:1），兩者都是指引，不是針對按鈕的規定。App Review Guidelines 全文搜尋「contrast」「WCAG」「legib」**零筆**，沒有任何對比比例的審核條款。
3. **【推論】系統自己在 tint 為系統藍時，prominent 按鈕的文字是純白（#FFFFFF）。** 兩個依據：Apple 自己 HIG 插圖（白色勾勾與白字落在 #0088FF／#0091FF 上，見 §3.4），以及本機實測的 `UIButton.Configuration.filled()` 與 SwiftUI `.borderedProminent`（填色 = 系統藍，文字 #FFFFFF；tint 換成紅、綠、橘文字仍是 #FFFFFF，所以系統不會依底色亮度自動換黑字）。**Apple 文件沒有明寫這件事。** `.glassProminent` 與「增強對比」下的實際文字色**沒有量到**（§3.5）。
4. **【建議】自訂 accent color 要提供四個變體是 HIG 的建議，不是硬性規定。** HIG Color：「make sure to supply light and dark variants, and an increased contrast option for each variant」；Xcode 文件對 AccentColor asset 則寫「if necessary」。見 §4。
5. **Apple Music 的主要填滿按鈕做法：沒有查到。** 沒有任何 Apple 一手文件或 WWDC 逐字稿描述它。附帶一個反證：Apple 自己 HIG 的 Music app 截圖，選取中的 tab 是**紅色**（#FA233B），不是藍色。見 §5。

## 1. 版本現況（本次實際查得）

| 項目 | 查得內容 | 來源 |
|---|---|---|
| HIG Color 頁最近更新 | change log 最新兩筆：**December 16, 2025**「Updated guidance for Liquid Glass.」、**June 9, 2025**「Updated system color values, and added guidance for Liquid Glass.」。2025-06-09 之前一筆是 February 2, 2024 | [Color › Change log](https://developer.apple.com/design/human-interface-guidelines/color)，取得 2026-10-02 |
| HIG Buttons 頁 | 最新兩筆：December 16, 2025（Liquid Glass 指引）、June 9, 2025（button styles and content） | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) |
| HIG Accessibility 頁 | 最新一筆 June 9, 2025（Assistive Access、Switch Control、Nutrition Labels）；March 7, 2025 曾「Expanded and refined all guidance」全面改版 | [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) |
| HIG Dark Mode 頁 | 最新一筆 August 6, 2024 | [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) |
| 現行 System colors 表的 OS 版本 | **HIG 沒有標示 OS 版本**。表是單一跨平台表（欄位：Name／SwiftUI API／Default (light)／Default (dark)／Increased contrast (light)／Increased contrast (dark)），只有一句備註「visionOS system colors use the default dark color values」。【推論】依 change log 日期 2025-06-09（WWDC25 當天）與本機實測，對應 iOS／iPadOS 26 世代起 | 同上 |
| 本機實測環境 | Xcode 27.0（27A266a）；iOS Simulator runtime iOS 26.5（23F77）、iOS 27.0（24A434） | `xcodebuild -version`、`xcrun simctl list runtimes` |

## 2. 問題 1：HIG 列出的系統色色碼

### 2.1 HIG 原文與適用範圍

- 【建議】「Avoid hard-coding system color values in your app. Documented color values are for your reference during the app design process. The actual color values may fluctuate from release to release, based on a variety of environmental variables. Use APIs like Color to apply system colors.」（[Color › System colors](https://developer.apple.com/design/human-interface-guidelines/color#System-colors)）。也就是說 HIG 色碼表是**設計參考值**，Apple 明說實際值會隨版本浮動，要靠 API。
- 【建議】HIG 對 iOS 另列動態前景色（label、secondaryLabel、link 等）與背景色（systemBackground 系列、grouped 系列）的**語意與 UIKit API 名稱**，但這張表**沒有 RGB**（同頁 › Platform considerations › iOS, iPadOS）。

### 2.2 System colors 表（HIG 文件值）

來源：[Color › Specifications › System colors](https://developer.apple.com/design/human-interface-guidelines/color#Specifications)，取得於 2026-10-02；每格 RGB 來自 DocC JSON 色票 alt 並經像素比對。**API 實測值**欄以 iOS 26.5 與 27.0 兩個 runtime 的 `UIColor.systemX`、`Color.x` 解析，四個外觀 × 四個顏色 = 16 格**全部與 HIG 一致**（兩個 runtime 結果相同）。

| 顏色（SwiftUI API） | Default（淺色） | Default（深色） | 增強對比（淺色） | 增強對比（深色） |
|---|---|---|---|---|
| **Blue**（`blue`） | 0,136,255　#0088FF | 0,145,255　#0091FF | 30,110,244　#1E6EF4 | 92,184,255　#5CB8FF |
| **Red**（`red`） | 255,56,60　#FF383C | 255,66,69　#FF4245 | 233,21,45　#E9152D | 255,97,101　#FF6165 |
| **Green**（`green`） | 52,199,89　#34C759 | 48,209,88　#30D158 | 0,137,50　#008932 | 74,217,104　#4AD968 |
| **Orange**（`orange`） | 255,141,40　#FF8D28 | 255,146,48　#FF9230 | 197,83,0　#C55300 | 255,160,86　#FFA056 |

另外 8 色的完整值（Yellow、Mint、Teal、Cyan、Indigo、Purple、Pink、Brown）在同一張 HIG 表，本文不重複；需要時用〈附錄 A〉的方法取。

色空間：色票 PNG 內嵌 sRGB 標記；API 解析出的 `UIColor.systemBlue` 等在 iOS 27.0 的原生色空間是 `kCGColorSpaceSRGB`，數值 0.5333／0.5686／0.1176／0.3608 等，換成 8 bit 與 HIG 相同。所以對比計算直接用這些 sRGB 8 bit 值是正確的。

## 3. 問題 2、3：API 是否一致、iOS 26／27 有沒有變動、prominent 按鈕規定

### 3.1 HIG 值與 API 解析值一致

- 【推論】API 實測值（iOS 26.5、iOS 27.0 simulator，bare process，顯式 trait collection）：`UIColor.systemBlue`、SwiftUI `Color.blue`、`Color.accentColor`、`UIColor.tintColor` 在四個外觀都解析成 #0088FF／#0091FF／#1E6EF4／#5CB8FF，與 §2.2 一致。`Color.red`／`green`／`orange` 同樣一致。
- 【推論】`Color.accentColor` 與 `UIColor.tintColor` 在**沒有 AccentColor asset 的 bare process** 解析成系統藍四變體。Apple 文件沒有明寫「預設 accent 就是系統藍」（[`Color.accentColor`](https://developer.apple.com/documentation/swiftui/color/accentcolor) 只寫「A color that reflects the accent color of the system or app」），這是實測結果。my-money 目前的 app 有自訂的 AccentColor asset，要用系統藍必須移除或清空它；**在真正的 app 裡的解析結果需要你自己再驗**。
- 【推論】`UIColor.link` 在同兩個 runtime 解析成 **#007AFF（淺）／#0984FF（深）**，也就是舊版藍，**與 `systemBlue` 不同**。HIG 沒有列 link 的 RGB。若 app 用 `link` 語意色當文字色，會跟 tint 色差一階。
- Apple 開發者文件本身**不列色值**：[`UIColor.systemBlue`](https://developer.apple.com/documentation/uikit/uicolor/systemblue) 只寫「A blue color that automatically adapts to the current trait environment.」；[`Color.blue`](https://developer.apple.com/documentation/swiftui/color/blue) 只寫「A context-dependent blue color suitable for use in UI elements.」。

### 3.2 iOS 26／27 有沒有變動

- 【建議】**系統色在 iOS 26 世代有改。** 三個一手依據：(1) HIG Color change log 2025-06-09「Updated system color values」；(2) WWDC25 [Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)（約 2:35）：「Our family of system colors has been adjusted in subtle but meaningful ways across Light, Dark and Increased Contrast appearances, so that they work in harmony with Liquid Glass, improving hue differentiation」；(3) 舊版 HIG 存檔（下節）與現行表的差異。
- 【推論】**iOS 26 → iOS 27 沒有變動。** 兩個 runtime 的解析值逐位元相同；HIG Color 頁 2025-06-09 之後只有 2025-12-16 的 Liquid Glass 指引更新，沒有再改色值。
- 【推論】iOS 26.0–26.4 與 iOS 18 以前沒有 runtime 可測；舊值只能從 HIG 存檔得知。

### 3.3 舊版 HIG 值（你憑記憶的色碼從哪來）

來源：[Wayback 存檔的 HIG color.json（2025-06-07 22:54 UTC）](https://web.archive.org/web/20250607225442id_/https://developer.apple.com/tutorials/data/design/human-interface-guidelines/color.json)，iOS 欄位（`ios-default-system*.png`、`ios-accessible-system*.png`）的 alt。這是 Apple 官方頁面的存檔，**不是 Apple 自己的主機**，標為舊值參考。

| 顏色 | 舊 Default（淺） | 舊 Default（深） | 舊增強對比（淺） | 舊增強對比（深） |
|---|---|---|---|---|
| Blue | #007AFF | #0A84FF | #0040DD | #409CFF |
| Red | #FF3B30 | #FF453A | #D70015 | #FF6961 |
| Green | #34C759 | #30D158 | #248A3D | #30DB5B |
| Orange | #FF9500 | #FF9F0A | #C93400 | #FFB340 |

舊值的白字對比：#007AFF 4.02、#0A84FF 3.65、#0040DD 7.56、#409CFF 2.83；黑字：5.23、5.76、2.78、7.42。與你的計算完全一致。現行值相對舊值：藍色變得更亮更飽和（淺色白字對比 4.02 → 3.52），增強對比（淺色）從深藍 #0040DD 變成 #1E6EF4（白字對比 7.56 → 4.57）。

【推論】觀察現行表：四色的「增強對比（淺色）」對白底的對比比全落在 4.54–4.57（藍 4.57、紅 4.56、橘 4.55、綠 4.54），看起來是 Apple 刻意調到剛好略高於 4.5:1；其他三個欄位沒有這個規律。這支持「增強對比（淺色）是設計來讓白底上的彩色文字或彩色底配白字過 AA」的讀法，但 Apple 沒有明說。

### 3.4 HIG 對 prominent／filled 按鈕的明文規定

**HIG Buttons**（[Style](https://developer.apple.com/design/human-interface-guidelines/buttons#Style)、[Role](https://developer.apple.com/design/human-interface-guidelines/buttons#Role)）：

- 【建議】「use a button that has a prominent visual style for the most likely action in a view. To draw people's attention to a specific button, use a prominent button style so the system can apply an accent color to the button's background.」每個 view 的 prominent 按鈕「one or two」。
- 【建議】「Use style — not size — to visually distinguish the preferred choice」。
- 【建議】Role：「a primary button uses an app's accent color, whereas a destructive button uses the system red color.」不要把 primary role 給破壞性按鈕。
- 【建議】「Avoid applying a similar color to button labels and content layer backgrounds.」
- **沒有**任何關於 prominent 按鈕**文字顏色**或**對比比例**的敘述。唯一提到「白底黑字」的是 visionOS 專屬的一句「Avoid creating a custom button that uses a white background fill and black text or icons. The system reserves this visual style to convey the toggled state.」，與 iOS 無關。

**HIG Color › Liquid Glass color**（[連結](https://developer.apple.com/design/human-interface-guidelines/color#Liquid-Glass-color)）：

- 【建議】「To emphasize primary actions, apply color to the background rather than to symbols or text. For example, the system applies the app accent color to the background in prominent buttons — such as the Done button — to draw attention and elevate their visual prominence. Refrain from adding color to the background of multiple controls.」
- 【建議】「Apply color sparingly … reserve it for elements that truly benefit from emphasis, such as status indicators or primary actions.」
- 【建議】prominent 樣式的實際背景是「colored or stained glass」（同節首段：「is the approach the system uses for prominent button styling」）。
- HIG [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)：「Use the `.prominent` style for key actions such as Done or Submit … Only specify one primary action, and put it on the trailing side」。

**Apple HIG 插圖中的 prominent 元件（【推論】，圖像像素取樣，不是文字規定）：**

| 插圖 | 取樣結果 |
|---|---|
| [Color 頁 Done 按鈕（淺色）](https://developer.apple.com/tutorials/images/com.apple.HIG/color-liquid-glass-overview-tinted@2x.png) | 填色 #0088FF（= 系統藍 Default 淺色）；勾勾 #FFFFFF |
| 同圖深色版（`~dark@2x`） | 填色 #0091FF（= 系統藍 Default 深色）；勾勾 #FFFFFF |
| [Buttons 頁 Role 範例 alert（淺色）](https://developer.apple.com/tutorials/images/com.apple.HIG/buttons-roles-alert@2x.png) | Primary 按鈕填色約 #0086FD，字 #FFFFFF；Destructive 是**文字** #FF383C（= 系統紅 Default 淺色）在灰色按鈕上，不是填滿 |

alt 文字分別是「a checkmark on a blue Liquid Glass background」與「The primary button uses a blue accent color」，沒有提到字色；字色是我從像素讀的。

### 3.5 系統 prominent 按鈕在 tint 為系統藍時的文字色（API 實測）

- 【推論】**`UIButton.Configuration.filled()`（淺色）與 SwiftUI `.borderedProminent`（淺色、深色）：填色 = 當時的系統 tint，文字 = #FFFFFF。** 在 `ImageRenderer` 離屏繪製下，iOS 26.5 與 27.0 結果相同：

  | tint | 淺色填色 | 深色填色 | 文字 |
  |---|---|---|---|
  | 預設／`.blue` | #0088FF | #0091FF | #FFFFFF |
  | `.red` | #FF383C | #FF4245 | #FFFFFF |
  | `.green` | #34C759 | #30D158 | #FFFFFF |
  | `.orange` | #FF8D28 | #FF9230 | #FFFFFF |

  文字核心像素是純白 #FFFFFF（315／319 個；其餘是抗鋸齒邊緣與底色混出的過渡色）。白字對比：綠色淺色 2.22:1、橘色淺色 2.31:1、紅色淺色 3.57:1，也就是**系統不保證 prominent 按鈕的文字對比 ≥ 4.5:1，連 3:1 都不保證**。
- 【推論】**沒有量到的部分**：(1) `.glassProminent`：`ImageRenderer` 離屏繪製是空白（改用 `UIWindow` 加 `drawHierarchy` 也是空白），無法取樣；`UIButton.Configuration.prominentGlass()` 沒有測。(2) 「增強對比」開啟時 prominent 按鈕的文字色：`ImageRenderer` 的環境 `colorSchemeContrast` 固定是 `standard`，我另開一個臨時 simulator 把系統「增強對比」打開驗證過，輸出完全沒變，所以這個方法量不到（臨時 simulator 已刪除）。UIKit 的 `traitOverrides` 在離屏 view 上也沒有生效（`trait seen` 仍是 light／normal）。**需要在真正的 app 畫面或 UI 測試截圖驗證**（專案已有 `scripts/screen-tour.sh`）。
- 【推論】若系統在「深色＋增強對比」仍用白字，會是白字在 #5CB8FF 上的 2.15:1；若系統改用黑字，則 9.76:1。**這點不知道，不能假設。**
- 【建議】Apple 文件對文字色沒有說明：[`borderedProminent`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/borderedprominent)「A button style that applies the standard bordered prominent style based on the button's context」；[`glassProminent`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent)（iOS 26.0+）「A button style that applies a prominent Liquid Glass effect based on the button's context」；[`UIButton.Configuration.filled()`](https://developer.apple.com/documentation/uikit/uibutton/configuration-swift.struct/filled())「a background filled with the button's tint color」；`baseForegroundColor`「The button configuration may transform the base color before applying it to foreground views」（[連結](https://developer.apple.com/documentation/uikit/uibutton/configuration-swift.struct/baseforegroundcolor)）。[`tint(_:)`](https://developer.apple.com/documentation/swiftui/view/tint(_:)) 另說：「Unlike an app's accent color, which can be overridden by user preference, the tint color is always respected」，並指出各平台、各樣式對 tint 套用到背景或標籤的方式不同（macOS 兩種樣式都不染標籤，「but they do in other platforms」），沒有說 prominent 的標籤用什麼顏色。

### 3.6 Liquid Glass 的 tint 與對比（WWDC25 一手資料）

- 【建議】[Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)（約 16:08–17:00）：「Selecting a color generates a range of tones that are mapped to content brightness underneath the tinted element」，tint 的色相、亮度、飽和度會隨背後內容變動，「helps legibility and contrast」。「Tinting should only be used to bring emphasis to primary elements and actions」。
- 【建議】同場（約 18:29）：Increased contrast「makes elements predominantly black or white and highlights them with a contrasting border」。這是 Liquid Glass 的增強對比行為：玻璃元件在增強對比下改成近乎黑白加邊框，**不再是 tint 色填滿**。
- 【建議】[Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)（約 19:12）：glass 上的 tint「uses a vibrant color that adapts to the content behind it」；[Build a UIKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/284/)：`.prominentGlass()`「to get glass tinted with your app's tint color」、「Tinted glass color automatically adapts to a vibrant version」；toolbar 的 prominent 樣式則是「To tint the button background, set the style to prominent」。
- 【推論】因此 `.glassProminent` 的實際底色**不是固定的 #0088FF**，會依背後內容與增強對比設定而變；用單一色碼算出的對比比例只適用於 `.borderedProminent`／`filled()` 這類實色填滿，對 `.glassProminent` 只是近似。

### 3.7 HIG 的對比比例與大字／粗體

**HIG Accessibility › Vision**（[連結](https://developer.apple.com/design/human-interface-guidelines/accessibility#Vision)）：

- 【建議】「Strive to meet color contrast minimum standards … Two popular standards of measure for color contrast are the Web Content Accessibility Guidelines (WCAG) and the Accessible Perceptual Contrast Algorithm (APCA). Use standard contrast calculators … Accessibility Inspector uses the following values from WCAG Level AA as guidance in determining whether your app's colors have an acceptable contrast.」

  | Text size | Text weight | Minimum contrast ratio |
  |---|---|---|
  | Up to 17 pts | All | 4.5:1 |
  | 18 pts | All | 3:1 |
  | All | Bold | 3:1 |

- 【建議】「If your app doesn't provide this minimum contrast by default, ensure it at least provides a higher contrast color scheme when the system setting Increase Contrast is turned on. If your app supports Dark Mode, make sure to check the minimum contrast in both light and dark appearances.」
- 【建議】「Prefer system-defined colors. These colors have their own accessible variants that automatically adapt when people adjust their color preferences, such as enabling Increase Contrast or toggling between the light and dark appearances.」

**HIG Dark Mode**（[Dark Mode colors](https://developer.apple.com/design/human-interface-guidelines/dark-mode#Dark-Mode-colors)）：

- 【建議】「At a minimum, make sure the contrast ratio between colors is no lower than 4.5:1. For custom foreground and background colors, strive for a contrast ratio of 7:1, especially in small text.」這句**沒有大字或粗體例外**，與 Accessibility 頁的表並列時，Apple 沒有說怎麼調和。
- 【建議】要在 Dark Mode 搭配 Increase Contrast 與 Reduce Transparency（分開與同時）下測試；「turning on Increase Contrast in Dark Mode can result in reduced visual contrast between dark text and a dark background」。

**HIG 表與 WCAG 的差異（【推論】）：**

- WCAG 2.2 的 [large scale](https://www.w3.org/TR/WCAG22/#dfn-large-scale) 定義是「at least 18 point or 14 point bold」；SC 1.4.3 對一般文字 4.5:1、大字 3:1；SC 1.4.11 另要求 UI 元件邊界與圖形物件對相鄰色 3:1。HIG 表寫的是「17 pt 以下一律 4.5:1」「18 pt 3:1」「Bold 3:1」，且 Bold 列沒有字級下限，與 WCAG 的「14 pt bold 起」不同；第一列與第三列對「≤17 pt 的粗體」也有重疊，Apple 沒有說以哪列為準。
- HIG 對比表是 Accessibility Inspector 的「guidance」，Apple 沒有說 17 pt／18 pt 是 CSS pt 還是 UIKit pt。
- App Review Guidelines（Last Updated: June 8, 2026）全文對「contrast」「WCAG」「legib」搜尋為零筆，所以對比比例**不是**審核條款。【推論】my-money 只走 TestFlight 內部測試，這個標準純屬自我要求。

### 3.8 對驗收標準的含義（【推論】，決策留給專案）

| 文字色／底色 | 淺色 | 深色 | 增強對比（淺） | 增強對比（深） | 通過 4.5:1 的外觀數 |
|---|---|---|---|---|---|
| 白字 on 系統藍（系統預設做法） | 3.52 | 3.23 | 4.57 | 2.15 | 1／4 |
| 黑字 on 系統藍 | 5.97 | 6.49 | 4.59 | 9.76 | 4／4 |
| 藍字 on `systemBackground`（淺 = 白、深 = 黑；borderless 按鈕與連結文字） | 3.52 | 6.49 | 4.57（白底） | 9.76（黑底） | 3／4 |

- 若驗收改寫成 HIG 表的「≥18 pt 或粗體 → 3:1」：白字在淺色、深色、淺色增強對比通過；**深色增強對比 2.15 仍不通過**。這一格是否真的用白字，要實測（§3.5）。
- 要讓白字在淺色外觀達到 4.5:1，底色的相對亮度必須 ≤ 0.1833（1.05 / 4.5 − 0.05）；系統藍 #0088FF 是 0.2483，所以「系統預設藍＋白字」在淺色外觀不可能達到 4.5:1。要達到就得自訂更深的藍並自備四個變體（§4），那就不是「用系統預設藍」了。
- 藍字（無底的 borderless 按鈕、連結）在淺色 3.52:1 也不到 4.5:1；在 `systemGroupedBackground`（#F2F2F7）上更低（3.15）。這同樣是系統預設行為。

## 4. 問題 4：自訂 accent color 是否要提供四個變體

- 【建議】**HIG 要求（措辭是 make sure）：** 「Make sure all your app's colors work well in light, dark, and increased contrast contexts … When possible, use system colors, which already define variants for all these contexts. If you define a custom color, make sure to supply light and dark variants, and an increased contrast option for each variant that provides a significantly higher amount of visual differentiation. Even if your app ships in a single appearance mode, provide both light and dark colors to support Liquid Glass adaptivity in these contexts.」（[Color › Best practices](https://developer.apple.com/design/human-interface-guidelines/color#Best-practices)）。
- 【建議】Adopting Liquid Glass：「If you do apply color to these elements, leverage system colors, or define a custom color with light and dark variants, and an increased contrast option for each variant.」（[Adopting Liquid Glass › Controls](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)）。
- 【建議】Xcode 文件：[Specifying your app's color scheme](https://developer.apple.com/documentation/xcode/specifying-your-apps-color-scheme)：「In your accent color set, you can specify different color values for light and dark appearances **if necessary**.」「You can also specify high-contrast versions of your colors by selecting the High Contrast checkbox.」做法：asset catalog 的 `AccentColor` color set，Attributes inspector 的 Appearances 選 Any, Dark，再勾 High Contrast；Build Settings 的「Global Accent Color Name」指向它（Xcode 會寫入 Info.plist 的 [`NSAccentColorName`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaccentcolorname)；Apple 建議用 build setting 而不是直接改 plist）。程式碼取用：SwiftUI `Color.accentColor`、UIKit `UIColor.tintColor`。
- 【建議】[Supporting Dark Mode in your interface](https://developer.apple.com/documentation/uikit/supporting-dark-mode-in-your-interface)：「Define custom colors in your asset catalog … specify different color values for both light and dark appearances. You can also specify high-contrast versions of your colors.」
- 【規定】沒有查到：App Review Guidelines 沒有任何關於 accent color 變體的條文。**四個變體是 HIG 的 best practice，不是規定。**
- 【推論】my-money 現有的 `src/App/MyMoney/Assets.xcassets/AccentColor.colorset/Contents.json` 已經是四變體格式（`appearances` 使用 `luminosity: dark` 與 `contrast: high`，共四個 entry，品牌粉紅），所以「改成系統藍」有兩條路：(a) 把四個 entry 改成 §2.2 的藍色值——但 Apple 明說不要硬編系統色（「Avoid hard-coding system color values」），值會隨版本浮動；(b) 移除自訂值、讓系統給預設 accent——實測是系統藍四變體，會自動跟系統調整。哪條路對，要看你要不要「跟著系統變動」。(b) 的 `Color.accentColor` 行為要在真正的 app 裡驗（§3.1）。
- 【推論】系統色是 UIKit／SwiftUI 的動態色，不需要自己做四變體；只有自訂色才需要。

## 5. 問題 5：Apple Music（Apple 自家 app）的主要填滿按鈕

**沒有查到一手依據。** 查過的位置：

- HIG Buttons、Color、Toolbars、Tab bars、Materials、Branding、Dark Mode、Accessibility 全文：提到 Music 的只有 Tab bars 頁的 MiniPlayer 與「在 Music app 自訂 tab bar」的敘述與截圖、Sidebars 頁的 visionOS 截圖，沒有任何描述 Music 內填滿按鈕的顏色、字色或對比。
- WWDC21 [Meet the UIKit button system](https://developer.apple.com/videos/play/wwdc2021/10064/)、WWDC25 219／356／323／284／359 逐字稿：提到 Music 只有 MiniPlayer、tab bar 與播放畫面，沒有按鈕規格。
- [Apple Design Resources](https://developer.apple.com/design/resources/)：是 Figma／Sketch 的 UI Kit，無法用 curl 取得內容，**未檢查**。
- App Review Guidelines：沒有提到。
- 沒有採用部落格、截圖網站或個人印象。

附帶一個一手資料的間接證據（**不是對填滿按鈕的規格**）：[HIG Tab bars 頁的 Music 截圖](https://developer.apple.com/tutorials/images/com.apple.HIG/tab-bar-with-accessory-expanded@2x.png)中，選取中的「Home」tab 圖示與文字是 #FA233B（像素取樣）。【推論】所以 Apple Music 的 accent 是紅色，不是系統藍；「比照 Apple Music 做藍底白字」的前提在一手資料上站不住。HIG Color 頁自己說「by contrast, in apps with primarily monochromatic content or backgrounds, choosing your brand color as the app accent color can be an effective way to tailor your app experience」——Apple 的 app 是用自己的品牌色當 accent，不是 Apple 規定的藍色。

## 6. 未查證或不確定的項目

1. **HIG System colors 表對應的 OS 版本：** 頁面沒有標示，我只能說依 change log 日期（2025-06-09）與兩個 runtime 的實測，適用 iOS 26 與 27。
2. **iOS 26.0–26.4 與 iOS 18 以前的實際解析值：** 沒有 runtime，未測。
3. **「增強對比」開啟時，`.borderedProminent`／`.glassProminent` 的文字色與底色：** 未實測（§3.5）；`.glassProminent` 在任何外觀下的渲染結果也未實測。
4. **系統為何用白字、有無自動選字色的邏輯：** Apple 文件沒有說明；實測看到「換成綠色／橘色仍是白字」，但沒有量到更多底色。
5. **實測方法的限制：** bare process、沒有 app bundle、沒有 AccentColor asset、`ImageRenderer` 離屏渲染，與真正 app 內的畫面可能有差；你要自己在 app 裡再驗證。
6. **Apple Music 填滿按鈕：** 沒有查到（§5）。
7. **Apple Design Resources 的 Figma／Sketch UI Kit：** 未取得，其中可能有 prominent 按鈕的標註。
8. **HIG Accessibility 表的 pt 單位與 Bold 的字級下限、與 Dark Mode 頁 4.5:1 無例外的矛盾：** Apple 沒有說明如何調和。
9. **`UIColor.link` 仍是舊藍的原因與是否為預期：** 只有實測值，Apple 文件與 HIG 沒有討論。

## 7. 來源清單（本次實際讀取，取得日期 2026-10-02）

**HIG**（DocC JSON 全文）
- [Color](https://developer.apple.com/design/human-interface-guidelines/color)（含 Specifications › System colors 表與色票 alt、change log）、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)、[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)、[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)、[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)、[Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)、[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Branding](https://developer.apple.com/design/human-interface-guidelines/branding)
- HIG 插圖像素取樣來源：`https://developer.apple.com/tutorials/images/com.apple.HIG/` 下的 `colors-unified-*@2x.png`（48 張）、`color-liquid-glass-overview-tinted@2x.png`（含 `~dark`）、`buttons-roles-alert@2x.png`、`tab-bar-with-accessory-expanded@2x.png`
- 舊版 HIG（存檔）：[color.json，2025-06-07 快照](https://web.archive.org/web/20250607225442id_/https://developer.apple.com/tutorials/data/design/human-interface-guidelines/color.json)

**Developer Documentation**（DocC JSON 全文）
- [`UIColor.systemBlue`](https://developer.apple.com/documentation/uikit/uicolor/systemblue)、[`Color.blue`](https://developer.apple.com/documentation/swiftui/color/blue)、[`Color.accentColor`](https://developer.apple.com/documentation/swiftui/color/accentcolor)、[`tint(_:)`](https://developer.apple.com/documentation/swiftui/view/tint(_:))
- [`borderedProminent`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/borderedprominent)、[`glassProminent`](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent)、[`UIButton.Configuration`](https://developer.apple.com/documentation/uikit/uibutton/configuration-swift.struct)（`filled()`、`borderedProminent()`、`prominentGlass()`、`baseForegroundColor`、`baseBackgroundColor`）
- [Specifying your app's color scheme](https://developer.apple.com/documentation/xcode/specifying-your-apps-color-scheme)、[`NSAccentColorName`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaccentcolorname)、[Supporting Dark Mode in your interface](https://developer.apple.com/documentation/uikit/supporting-dark-mode-in-your-interface)、[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

**WWDC 逐字稿**
- WWDC25：[Meet Liquid Glass（219）](https://developer.apple.com/videos/play/wwdc2025/219/)、[Get to know the new design system（356）](https://developer.apple.com/videos/play/wwdc2025/356/)、[Build a SwiftUI app with the new design（323）](https://developer.apple.com/videos/play/wwdc2025/323/)、[Build a UIKit app with the new design（284）](https://developer.apple.com/videos/play/wwdc2025/284/)、[Design foundations from idea to interface（359）](https://developer.apple.com/videos/play/wwdc2025/359/)
- WWDC21：[Meet the UIKit button system（10064）](https://developer.apple.com/videos/play/wwdc2021/10064/)

**其他**
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)（Last Updated: June 8, 2026；對 contrast／WCAG／legib 搜尋零筆）
- [Apple Design Resources](https://developer.apple.com/design/resources/)（只確認為 Figma／Sketch 檔，未取得內容）
- [W3C WCAG 2.2](https://www.w3.org/TR/WCAG22/)：relative luminance、contrast ratio、large scale、SC 1.4.3、SC 1.4.11

## 8. 單色玻璃按鈕實測（#134，【推論】本機實測）

**實測日期**：2026-10-02。**環境**：Xcode 27.0、iOS Simulator iPhone 17（iOS 26.5），app 內的暫時畫面（用完已刪除），`AccentColor` 資產是單色（淺色黑、深色白，增強對比同）。外觀用 `xcrun simctl ui <device> appearance light|dark`、`increase_contrast enabled|disabled` 切換，`xcrun simctl io screenshot` 截圖後目視並用像素取樣確認。**沒有**驗證 iOS 26.0–26.4 與 iOS 27.0 的 runtime。

| 項目 | 淺色 | 深色 | 淺色增強對比 | 深色增強對比 |
|---|---|---|---|---|
| `.buttonStyle(.glass)`（字用主要文字色） | 白色玻璃膠囊、黑字，正常 | 深色玻璃膠囊、白字，正常 | 同左，外框略清楚 | 同左 |
| `.glassProminent`（accent 單色，**沒有**指定字色） | 黑底白字，正常 | **白底白字，字幾乎看不見** | 同淺色 | **同深色，看不見** |
| `.glassProminent` + 標籤明確指定 `foregroundStyle(系統背景色)` | 黑底白字 | 白底黑字 | 同 | 同 |
| `.glassProminent` + `.tint(.primary)`（沒指定字色） | 黑底白字 | 白底白字（同上） | 同 | 同 |
| 自訂 `ButtonStyle`（`Capsule` 填 `.primary`、字用系統背景色） | 黑底白字 | 白底黑字 | 同 | 同 |
| toolbar `Button(role: .cancel)`（`xmark`） | 白色玻璃圓鈕、黑 ✕ | 深色玻璃圓鈕、白 ✕ | 同 | 同 |
| toolbar `Button(role: .confirm)`（`checkmark`） | 黑色填滿圓鈕、白勾 | 白色填滿圓鈕、黑勾 | 同 | 同 |
| 「…」`Menu` + `.glass` + `.circle` | 白色玻璃圓鈕 | 深色玻璃圓鈕 | 同 | 同 |
| 一組 `ToolbarItemGroup` | 單一玻璃膠囊，圖示黑 | 單一玻璃膠囊，圖示白 | 同 | 同 |
| 停用的 `.glass`、`.glassProminent` | 淡化，仍看得出是按鈕 | 淡化 | — | — |

結論：

1. **`.glass` 四種外觀都能直接用**，不需要自訂樣式。
2. **`.glassProminent` 的字固定是白色**（跟 §3.5 的 `borderedProminent` 一致）:accent 在深色是白色時變成白底白字，**一定要明確指定反色字**。把反色字放在標籤裡面（`Button { label.foregroundStyle(...) }`）有效;只靠 `.tint(.primary)` 不行。不需要退到自訂 `ButtonStyle`，但保留為備案。
3. toolbar 的 `Button(role: .cancel)` 加 `systemImage: "xmark"` 是 ✕ 玻璃圓鈕，`Button(role: .confirm)` 加 `systemImage: "checkmark"` 是單色填滿的 ✓ 圓鈕;**系統依 accent 自動選反色的勾**，淺色黑底白勾、深色白底黑勾，不用自己處理。給了標題時（`Button("儲存", role: .confirm)`）會畫成帶文字的膠囊，沒有圖示，所以要同時給 `systemImage`;標題仍是 VoiceOver 的標籤。
4. 這些系統玻璃圓鈕的畫面尺寸是 36pt，UI 測試在圓鈕外 4pt 點得到（觸控範圍外擴到 44pt）。
5. **降低透明度**:嘗試用 `defaults write com.apple.Accessibility ReduceTransparencyEnabled` 在模擬器切換，截圖看不出差異，**無法確認模擬器有套用**，所以這一項沒有實測結果，只能依 HIG「系統控制項自動處理」的說法;真機要另外確認。增強對比有實測（上表）。

## 附錄 A：實測與重現方式

**取 HIG 色值**：

```bash
curl -s https://developer.apple.com/tutorials/data/design/human-interface-guidelines/color.json \
  | python3 -c "import json,sys; r=json.load(sys.stdin)['references']; print(r['colors-unified-blue-light.png']['alt'])"
# 印出 R-0,G-136,B-255；其餘鍵名：colors-unified-{red,orange,…}-{light,dark}.png、
# colors-unified-accessible-{…}-{light,dark}.png
```

**API 解析（API 實測值）**：以 `xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios26.0-simulator main.swift -o probe` 編譯，再用 `xcrun simctl spawn <已開機 simulator 的 UDID> ./probe` 執行（兩個 runtime 各跑一次）。核心片段：

```swift
let tc = UITraitCollection { $0.userInterfaceStyle = .dark; $0.accessibilityContrast = .high }
let c = UIColor.systemBlue.resolvedColor(with: tc)
let srgb = CGColorSpace(name: CGColorSpace.extendedSRGB)!
let comps = c.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil)!.components!
// 轉 8 bit：Int((comps[0] * 255).rounded())
```

SwiftUI 的 `Color.resolve(in:)` 只能設 `colorScheme`（`colorSchemeContrast` 是 get-only），所以增強對比以 `UIColor(Color.blue).resolvedColor(with:)` 驗證。按鈕渲染用 `ImageRenderer(content: Button("Save"){}.buttonStyle(.borderedProminent).controlSize(.large)…)`，背景墊品紅色（#FF00FF）以便分離文字像素，統計像素色值。實測過程中另建了一個臨時 simulator（`xcrun simctl create`）打開「增強對比」確認方法無效，已刪除；兩個既有 simulator 沒有被改設定。

**對比計算**（Python，WCAG 2.2 公式，與上文 §結論一致）：

```python
def lin(c): c /= 255; return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def L(rgb): r, g, b = map(lin, rgb); return 0.2126 * r + 0.7152 * g + 0.0722 * b
def cr(a, b): la, lb = sorted((L(a), L(b)), reverse=True); return (la + 0.05) / (lb + 0.05)
```

## 附錄 B：CI 色票的對比（2026-10-04，ADR-0009）

CI 色分成填色（淺深同一個 `#E23C52`）與文字（淺色 `#AD1F32`、深色 `#F88191`）。用上面同一個 WCAG 公式算出：

| 組合 | 對比 |
|---|---|
| 白字在 `#E23C52` | 4.2:1 |
| `#E23C52` 在白／淺灰 `#F2F2F7`／黑／深色卡片 `#1C1C1E`／次層卡片 `#2C2C2E` | 4.2／3.8／5.0／4.1／3.3 |
| `#AD1F32` 在白／淺灰 | 7.0／6.2 |
| `#F88191` 在黑／深色卡片／次層卡片 | 8.5／6.9／5.7 |
| 增強對比：白字在 `#881121`；黑字在 `#FDA5B1` | 9.8；9.1 |

同一個中間亮度的紅，在白底與黑底都 ≥ 3:1，所以填色能共用；文字要 4.5:1，單一色碼只在亮度 0.175～0.183 這個窄範圍同時對兩種底達標，所以文字分淺深兩個變體。實作與測試見 `CIPalette`、`CIPaletteTests`。
