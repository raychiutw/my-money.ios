# Apple 平台規範研究：my-money.ios（原生 SwiftUI 記帳 app）適用性

查核日期：2026-09-28（Asia/Taipei）

查核範圍：Apple Human Interface Guidelines（含 [What's new](https://developer.apple.com/design/whats-new/) 與各頁 change log）、[App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)（頁面標示 Last Updated: June 8, 2026）、Apple Developer Documentation、[Apple Developer News](https://developer.apple.com/news/) 與 [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)、WWDC26 session 頁面（含官方逐字稿）、Apple Newsroom。只引一手來源。本文件是規範研究與工程推論，**不是**對 my-money 既有程式碼、畫面或後端的稽核，也沒有做真機驗證。

## 研究方法與規範層級

HIG 與開發者文件網頁由 JavaScript 渲染，本次一律改抓官方 DocC JSON（例如 [tab-bars.json](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/tab-bars.json)、`/tutorials/data/documentation/<path>.json`），以全文而非搜尋摘要為準；Review Guidelines、Developer News、Newsroom、App Store Connect Help 是伺服器端 HTML，直接讀全文。行內連結一律指向可閱讀的官方網頁。

每條論點標示三種層級之一：

- **【規定】**：App Store Review Guidelines 條文，或 Apple 官方明文、違反會導致退件／無法上傳／功能被系統拒絕的硬性要求。後者另標 **【規定·技術】**。條文措辭是 *should* 的另註「軟性」。
- **【建議】**：HIG 的 best practice（prefer / consider / avoid 等）。HIG 不是逐條審核清單；Review Guidelines 第 4 節只說 "the following are minimum standards for approval"（[4. Design](https://developer.apple.com/app-store/review/guidelines/#design)）。
- **【推論】**：研究者把前兩者套用到 my-money.ios 的工程判斷，不是 Apple 原文。

唯一一處本機實測（zh_Hant_TW 格式化輸出，§13）是在 macOS 26.5.2 的 Foundation 上執行，歸類為【推論】並附註。

## 版本現況（本次實際查得）

| 項目 | 查得內容 | 來源 |
|---|---|---|
| 最新 iOS 正式版 | **iOS 27 / iPadOS 27，2026-09-14 發布**，支援 iPhone 11 and later；同日另發 iOS 26.7 | [Newsroom：Major updates … now available](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/)、[Apple security releases](https://support.apple.com/en-us/100100) |
| 下一版 | iOS 27.2 beta 於 2026-09-16 開放；**iPhone Duo（首款折疊 iPhone）2026-10-23 上市，出貨搭載 iOS 27.1**；Xcode 27.1 beta 於 9/18 提供 | [News 2026-09-16](https://developer.apple.com/news/?id=rfb1rooi)、[News 2026-09-18](https://developer.apple.com/news/?id=nyuppv9r) |
| SDK 要求 | 2026-04-28 起上傳需以 Xcode 26／iOS 26 SDK 建置；2026-09-09 起 deployment target 需 ≥ iOS 13；**2027 年 4 月起需 iOS 27 SDK** | [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)、[Developer News 2026-09-09](https://developer.apple.com/news/?id=k1mtkt1k) |
| Review Guidelines | Last Updated: June 8, 2026（本輪變更：Introduction 兒少安全、1.2、4.3(a)(b)、4.5.3） | [Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)、[News 2026-06-08](https://developer.apple.com/news/?id=a233fmpw) |
| HIG 改版 | 年度改版 **2026-06-08**（WWDC26：Design principles 重新推出，Tab bars、Search fields、Searching、Sidebars、Scroll views、Menus、App icons 更新）；最近一次 guidance 更新 **2026-09-17**（Apple In-App Purchase 改名）與 **2026-09-09**（新增 Designing for iPhone Duo，Layout、Branding 更新）；9/17 釋出 iOS/iPadOS 27 Figma UI Kit | [What's new](https://developer.apple.com/design/whats-new/) |
| Liquid Glass | 2025（iOS 26）導入。iOS 27 調整：更能擴散背後內容、加 darkened edge 與更亮 specular highlight；**Settings 新增 slider，使用者可從 ultra clear 調到 fully tinted**；app icon 渲染更銳利、可選 refraction。已採用者不需重新編譯即自動套用 | [WWDC26 Platforms State of the Union](https://developer.apple.com/videos/play/wwdc2026/102/)、[Newsroom](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/) |
| 舊設計退出開關 | `UIDesignRequiresCompatibility`：「The system ignores this key when you build for iOS 27 or later」 | [UIDesignRequiresCompatibility](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)、[SOTU](https://developer.apple.com/videos/play/wwdc2026/102/) |
| iPhone app 可縮放 | iOS 27 起 iPhone app 在 iPhone Mirroring 與 iPad 上可 resize，以最新 SDK 重編即自動 opt in | [SOTU](https://developer.apple.com/videos/play/wwdc2026/102/)、[What's new in SwiftUI（WWDC26）](https://developer.apple.com/videos/play/wwdc2026/269/) |

## 結論

1. **【規定】帳號刪除是上架 blocker。** 只要 app 支援建立帳號，就「must also offer account deletion within the app」（[5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)）；只提供停用不夠；非高度監管產業不得要求打電話、寄 email 或走客服流程（[Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/)）。**【推論】** 後端沒有刪除 endpoint，iOS 版就無法合規送審，必須先補後端（可接受非同步／人工處理，但要從 app 內發起並告知時程，詳見 §9.4）。
2. **【規定】Sign in with Apple 目前不是必要項目。** 4.8 只在「使用第三方或社群登入服務建立／驗證主要帳號」時才要求另提供等價登入選項，而且「exclusively uses your company's own account setup and sign-in systems」被明列為例外（[4.8](https://developer.apple.com/app-store/review/guidelines/#login-services)）。**【推論】** LINE/Telegram bot 綁定不是登入主帳號，不觸發 4.8；日後若加入「用 LINE 登入」就會觸發。
3. **【規定】隱私四件套**：App Store Connect 與 app 內都要有隱私權政策連結（[5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)）；送審時要填 App Privacy 資料（[HIG Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)、[2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)）；有用到 required reason API（例如 `UserDefaults`）卻沒寫進 privacy manifest 的 app，App Store Connect 不收（[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)）；用 Face ID 必須有 `NSFaceIDUsageDescription`（[文件](https://developer.apple.com/documentation/bundleresources/information-property-list/nsfaceidusagedescription)）。
4. **【規定】送審要附可用的 demo 帳號、後端要開著**（[2.1(a)](https://developer.apple.com/app-store/review/guidelines/#app-completeness)）；截圖要用虛構帳務資料，不能用真人資料（[2.3.9](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)）。
5. **【規定·技術】新 app 沒有退回舊設計的選項。** 以 iOS 27 SDK 建置時系統會忽略 `UIDesignRequiresCompatibility`，而 2027 年 4 月起又強制 iOS 27 SDK（見版本現況）。**【推論】** 從第一天就用標準 SwiftUI 元件承接 Liquid Glass，不要自刻 bar 背景。
6. **【推論】金融條款風險要在送審說明處理。** [3.2.1(viii)](https://developer.apple.com/app-store/review/guidelines/#acceptable) 說「financial trading, investing, or money management」類 app 應由提供該服務的金融機構提交；[5.1.1(ix)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) 說 banking and financial services 等高度監管領域應由法人而非個人開發者提交。手動記帳、不經手資金、不連銀行，研判多半不屬於這兩類，但「money management」沒有官方定義（未查證），建議在 App Review notes 明寫不連接金融機構、不移轉資金、不提供投資建議。
7. **【建議】導覽骨架**：`TabView` 用於頂層區域導覽，**不要把「新增交易」做成 tab**（「Use a tab bar to support navigation, not to provide actions」），不要停用或隱藏 tab，避免 More overflow；iPad 用 `sidebarAdaptable` 讓 tab bar 可轉成 sidebar（[Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)、[Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)）。
8. **【建議】Liquid Glass 只給控制層與導覽層**：「Don't use Liquid Glass in the content layer」，內容層（帳戶卡、交易列、預算、圖表）用 standard materials 與系統背景色；自訂 glass 效果節制使用（[Materials](https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass)）。
9. **【建議】以可用空間、而非裝置型號做版面**：依 size class 排版，size class 改變時功能不變（[Layout](https://developer.apple.com/design/human-interface-guidelines/layout#Size-classes)）。iPhone Duo 會把 toolbar/tab bar 移到側邊，toolbar item 要同時給 title 和 symbol（[Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo#Vertical-controls)）。
10. **【建議】無障礙基線**：文字可放大到至少 200%、觸控目標預設 44×44 pt（最小 28×28 pt）、文字對比依 WCAG AA、不只靠顏色傳達資訊、對 Reduce Motion 有回應（[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)）；圖表要逐元素提供 accessibility label，Swift Charts 預設附 Audio Graphs（[Charts](https://developer.apple.com/design/human-interface-guidelines/charts#Enhancing-the-accessibility-of-a-chart)）。**【推論】** 收入／支出不能只靠紅綠色區分。
11. **【建議】金額輸入**：用 number formatter／FormatStyle 綁定數值、顯示對應的數字鍵盤（[Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields)、[Virtual keyboards](https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards)）；Apple 文件明寫「don't use Float or Double to represent currency … Use Decimal」（[Preparing dates, currencies, and numbers](https://developer.apple.com/documentation/xcode/preparing-dates-numbers-with-formatters)）。
12. **【建議】破壞性動作分級**：常見、可復原的刪除不要跳 alert（改提供 undo）；少見且不可復原的才確認；刻意動作的後續選擇用 action sheet（confirmation dialog），destructive 按鈕放最上面並附 Cancel（[Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)、[Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets)）。
13. **【建議】安全**：敏感資訊存 Keychain、不存純文字檔（[Privacy › Protecting data](https://developer.apple.com/design/human-interface-guidelines/privacy#Protecting-data)）；對保持登入的 app 可用 Face ID／Touch ID 加一層保護（同頁）；通知不放敏感資訊（【規定】[4.5.4](https://developer.apple.com/app-store/review/guidelines/#apple-sites-and-services)，軟性 should）。
14. **【推論】zh-Hant-TW 格式要明確設定**：本機實測 `Decimal.formatted(.currency(code: "TWD"))` 在 zh_Hant_TW 輸出 `$12,345.67`（兩位小數、符號是 `$` 不是 `NT$`），整數台幣應明確設 `precision(.fractionLength(0))`；使用者可能把行事曆設成民國曆，顯示走 locale、API 傳輸走 ISO 8601。
15. **【建議】若只給自己家人用，可以不上 App Store。** Review Guidelines 前言原文：「If you build an app that you just want to show to family and friends, the App Store isn't the best way to do that」，建議用 Xcode 直接安裝或 Ad Hoc（[Introduction](https://developer.apple.com/app-store/review/guidelines/#introduction)）。**【推論】** 這樣可以暫時避開帳號刪除缺口與金融條款疑慮；一旦公開上架，1、3、4、6 條全部要處理。

---

## 1. App 結構與導覽

### 1.1 Tab bar

- 【建議】Tab bar 用於在 app 頂層區段間導覽，並保留各區段內的導覽狀態；對目前畫面元素的操作應放 toolbar（[Tab bars › Best practices](https://developer.apple.com/design/human-interface-guidelines/tab-bars)）。
- 【建議】切換區段時要讓 tab bar 保持可見，modal 覆蓋時例外（同上）。
- 【建議】tab 數量以使用頻率權衡，越少越好導覽；資訊架構複雜時考慮 sidebar 或可轉 sidebar 的 tab bar（同上）。
- 【建議】避免 overflow：水平空間不足時最後一個 tab 會變成 More，內容較難被發現（同上）。
- 【建議】「Don't disable or hide tab bar buttons, even when their content is unavailable」；區段沒內容時說明原因（同上）。
- 【建議】每個 tab 附文字 label（盡量單字）；用 SF Symbols，偏好 filled 變體；badge 只用於需要注意的關鍵資訊（同上）。
- 【建議】內容層顏色鮮豔時，tab bar 用 monochromatic 外觀或差異夠大的 accent color（同上；[Color › Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color#Liquid-Glass-color)）。
- 【建議】iOS：tab bar 浮在內容上方，底層是 Liquid Glass；可選擇捲動時縮小（[TabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior)）；可在尾端放專屬 search tab（[Tab bars › iOS](https://developer.apple.com/design/human-interface-guidelines/tab-bars)）。搜尋 tab 要用系統語意 API `Tab(role: .search)`，系統會把它分開放到尾端（[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)）。
- 【建議】iPadOS：tab bar 在畫面頂部，可固定或附按鈕轉成 sidebar（[tabBarOnly](https://developer.apple.com/documentation/swiftui/tabviewstyle/tabbaronly)／[sidebarAdaptable](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable)）；若開放自訂 tab，預設清單以 5 個以內為目標（[Tab bars › iPadOS](https://developer.apple.com/design/human-interface-guidelines/tab-bars)）。
- 【推論】WWDC26 新增 `TabRole.prominent`，可把特殊 tab 放到底部尾端（範例是購物車）（[What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/)、[TabRole](https://developer.apple.com/documentation/swiftui/tabrole)）。它仍然是**導覽**目的地，不是動作按鈕，不應拿來開「新增交易」sheet。
- 【推論】iOS 27 release notes 記載：以 iOS 27 SDK 建置時，`TabView` 會強制 selection 必須是可見的 tab，選到隱藏 tab 可能 crash（[iOS & iPadOS 27 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)）。這條剛好跟 HIG「不要隱藏 tab」一致，不要用隱藏 tab 做權限控管（例如非家庭成員看不到「家庭」tab）。
- 【推論】my-money 骨架建議 4~5 個 tab：**總覽**（餘額、30 天現金流預測、「買得起嗎」入口）、**交易**、**規劃**（月預算、固定收支、儲蓄目標）、**分析**（圖表）、**設定**（帳戶管理、家庭群組、LINE/Telegram 綁定、CSV 匯出、帳號）。控制在 5 個以內，避免 iPhone 出現 More。「新增交易」放各頁 toolbar 的主要動作（見 1.3），另可用 widget（§12）提供快速入口。

### 1.2 Sidebar、split view 與 iPad

- 【建議】Sidebar 需要大量空間；很多 app 不必二選一，可用能提供兩者的 tab bar 樣式（[Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)）。
- 【建議】iOS/iPadOS 使用 `sidebarAdaptable` 時，由你決定開啟時顯示 sidebar 還是 tab bar，兩者都附切換按鈕，並會自動回應旋轉與視窗縮放；「Consider using a tab bar first」（[Sidebars › iOS, iPadOS](https://developer.apple.com/design/human-interface-guidelines/sidebars)）。
- 【建議】Sidebar 一般不超過兩層階層；更深就改用 split view，在 sidebar 與 detail 間加一欄內容清單（同上）。Sidebar icon 預設使用 app accent color（同上，2026-06-08 更新）。
- 【建議】Split view 偏好在 regular 環境使用；iPad 視窗可連續縮放，要考慮窄、中、寬各種寬度；持續高亮通往 detail 的目前選取項（[Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)）。
- 【建議】空間變大時可把 tab bar 換成 sidebar，或把原本收在 overflow 的功能露出來，但**功能本身不要隨空間改變**（[Layout › Size classes](https://developer.apple.com/design/human-interface-guidelines/layout#Size-classes)）。
- 【建議】iPad：善用大螢幕凸顯內容，減少 modal 與全螢幕轉場（[Designing for iPadOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados)）。
- 【規定，軟性】「iPhone apps should run on iPad whenever possible」（[2.4.1](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)）。
- 【推論】my-money：根層 `TabView` + `.tabViewStyle(.sidebarAdaptable)`；「交易」在 regular width 用 `NavigationSplitView`（交易列表 + 明細），compact 時自動收成 stack。資料量不大，iPad 第一版做到「同一套 SwiftUI 版面會伸縮」即可，不需要另做 iPad 專屬功能。

### 1.3 Navigation stack 與 toolbar

- 【建議】toolbar 項目要精選、避免擁擠，並定義寬度變窄時哪些項目進 overflow；iOS 空間有限，只放最重要的項目，其餘放 More 選單（[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)）。
- 【建議】減少自訂 toolbar 背景與著色控制項，改用內容層決定顏色，必要時用 `ScrollEdgeEffectStyle` 區隔（同上）。
- 【建議】標題：每個畫面給有用的標題，**不要用 app 名稱當標題**，建議 15 個字元以內；iOS 用 large title 幫助定位（同上 › Titles、iOS）。
- 【建議】「Use the standard Back and Close buttons」，偏好標準符號，不要用寫著 Back／Close 的文字 label（同上 › Navigation）。
- 【建議】Done、Submit 這類關鍵動作用 `.prominent` 樣式，**只指定一個 primary action 並放在 trailing**（同上 › Actions）。
- 【建議】toolbar 分組依功能與使用頻率，一般最多三組；有文字 label 的動作與 symbol 動作要分開（同上 › Item groupings）。
- 【建議】iPhone Duo：系統會把 toolbar、tab bar、navigation controls 移到側邊；上方保留給 Back／Close，接著是 Done 等顯著動作；替 toolbar item 設 visibility priority；**每個非純文字的 toolbar item 都同時提供 title 與 symbol**；純文字按鈕留在水平 bar，能用 symbol 就用；一般不要覆寫系統的 bar 位置；app 自己的 overflow 選單改用系統 overflow menu（[Designing for iPhone Duo › Vertical controls](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo#Vertical-controls)）。
- 【規定·技術】iPhone Duo 呈現規則：只有 title 沒有 icon 的 item、或用自訂 view 的 item，系統不會把它放進直向 bar；以 Xcode 26 或更早版本建置的 app 不會延伸到狀態列與相機下方（[Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)）。
- 【推論】相關 SwiftUI API（本次確認文件存在）：[`visibilityPriority(_:)`](https://developer.apple.com/documentation/swiftui/toolbaritemvisibilitypriority)、[`ToolbarOverflowMenu`](https://developer.apple.com/documentation/swiftui/toolbaroverflowmenu)、[`topBarPinnedTrailing`](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/topbarpinnedtrailing)、[`toolbarMinimizationBehavior(_:for:)`](https://developer.apple.com/documentation/swiftui/view/toolbarminimizationbehavior(_:for:))（iOS 27 release notes：取代 `toolbarMinimizeBehavior`）。
- 【推論】my-money：「交易」頁 trailing 放「新增」（`.prominent`、`topBarPinnedTrailing`、同時給 `Label("新增交易", systemImage: …)`）；篩選、匯出這類低頻動作放系統 overflow。sheet 內用語意 placement `.cancellationAction`／`.confirmationAction`，讓系統決定符號與位置。

### 1.4 Search

- 【建議】搜尋重要就給它主要位置；盡量讓內容能從**單一位置**搜到，區段分明時仍可提供局部搜尋；清楚顯示目前搜尋範圍；提供最近搜尋／建議；**顯示搜尋紀錄前先考慮隱私，並提供清除方式**（[Searching](https://developer.apple.com/design/human-interface-guidelines/searching)）。
- 【建議】iOS 搜尋入口有三種：tab bar 裡的 tab、上／下方 toolbar、內容旁的 inline field。有空間就放底部；需要讓出底部內容時才放頂部；inline field 適合只搜目前清單，放在清單上方並可在捲動時 pin 到 toolbar（[Search fields › iOS](https://developer.apple.com/design/human-interface-guidelines/search-fields)）。
- 【建議】用 scope bar 過濾明確類別、預設範圍較廣；token 用於常用條件（[Search fields › Scope bars and tokens](https://developer.apple.com/design/human-interface-guidelines/search-fields#Scope-bars-and-tokens)）。
- 【推論】my-money：搜尋主要對象是交易，放在「交易」tab 用 [`searchable(text:placement:prompt:)`](https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:))；分類、帳戶、公帳／私帳做成 token 或 scope。交易金額與備註屬財務資料，**不建議預設索引進 Spotlight**（HIG 的搜尋紀錄隱私原則延伸）。

### 1.5 iPhone Duo 與可縮放

- 【建議】為縮放而建：用 size class、layout margins、safe area insets，避免固定寬度與綁定特定螢幕；外螢幕用 compact width、內螢幕用 regular width 的版面就涵蓋所有姿勢；可用 Device Hub 預覽各種姿勢（[Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)）。
- 【建議】在不同螢幕間保持功能與狀態一致，大螢幕可多顯示一層階層（例如 Mail 開啟時列表與內文並列）；折疊時避免劇烈重排；grid 版面偏好偶數欄；自訂元件用 [`ReservedRegion`](https://developer.apple.com/documentation/swiftui/reservedregion) 避開相機與折疊區（同上 › Dynamic layouts）。
- 【推論】以 SwiftUI 標準容器（`TabView`、`NavigationStack`、`NavigationSplitView`、`Form`、`List`）為主的記帳 app，大部分會自動適應；要實測的是自訂的金額鍵盤、分類 grid、圖表寬度。

## 2. Liquid Glass 與 materials

- 【建議】Liquid Glass 是浮在內容層之上、給控制與導覽元素（tab bar、sidebar）使用的獨立功能層（[Materials › Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials#Liquid-Glass)）。
- 【建議】「Don't use Liquid Glass in the content layer」；內容層（例如 app 背景）用 standard materials。例外是 slider、toggle 這類有短暫互動的內容層控制項，互動時會自動變成 glass（同上）。
- 【建議】「Use Liquid Glass effects sparingly」：標準元件會自動取得；自訂控制項只套用在最重要的功能元素（同上；開發指引見 [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)）。
- 【建議】glass 有 regular 與 clear 兩種變體：regular 會模糊背景以維持可讀性，多數系統元件使用；clear 高度透明，**只用在浮於照片／影片等視覺豐富背景之上的元件**；兩者外觀都會回應使用者選的 Liquid Glass 偏好、Reduce Transparency 與 Increase Contrast（同上）。
- 【建議】iOS/iPadOS 內容層仍有 ultra-thin、thin、regular、thick 四種 standard materials；material 上的文字用 vibrant 系統色，thin／ultraThin 上避免 quaternary（[Materials › iOS, iPadOS](https://developer.apple.com/design/human-interface-guidelines/materials#Standard-materials)）。
- 【建議】區隔控制與內容：不要在控制項下墊實色或半透明背景，改用 scroll edge effect（[Layout › Visual hierarchy](https://developer.apple.com/design/human-interface-guidelines/layout)）；scroll edge effect 不是裝飾，只在 scroll view 位於浮動元素之下時使用，每個 view 一個，偏好 automatic 樣式（[Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views)）。
- 【建議】Liquid Glass 顏色：預設沒有固有顏色，取自背後內容；顏色只留給真正需要強調的元素（狀態指示、主要動作），強調主要動作時上色在背景而非文字；不要替多個控制項背景上色（[Color › Liquid Glass color](https://developer.apple.com/design/human-interface-guidelines/color#Liquid-Glass-color)）。
- 【建議】品牌色：accent color 節制使用，主要用於 primary action 或狀態指示；想表達品牌色可移到內容層，讓它在 glass 控制項下方被動態取色（[Branding](https://developer.apple.com/design/human-interface-guidelines/branding)，2026-09-09 更新）。
- 【建議】遷移清單：移除 `NavigationStack`、toolbar 等的自訂背景；用各種顯示與無障礙設定測試；避免 glass 疊 glass；自訂 bar 用 [`safeAreaBar`](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:)) 取得 scroll edge effect；按鈕優先用 `.glass`／`.glassProminent` 樣式而非自己套效果；sheet 圓角加大、half sheet 內縮，要檢查邊緣內容；action sheet 從觸發元件長出來，要設定 source；**每個 icon 都要有 accessibility label**（[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)）。
- 【推論】my-money：帳戶卡、交易列、預算進度條、圖表全部是內容層，用 `systemGroupedBackground` 系列與 standard material，不套 `glassEffect`。唯一可能需要自訂 glass 的，是浮在內容上方的自訂控制（例如圖表上方浮動的期間切換器）；能改用 toolbar 裡的標準 `Picker` 就不要自訂。

## 3. Typography、color、SF Symbols、App icon

### 3.1 Typography 與 Dynamic Type

- 【建議】讓使用者能放大文字，理想是至少 200%；可用 Dynamic Type 達成（[Accessibility › Vision](https://developer.apple.com/design/human-interface-guidelines/accessibility)）。自訂字級時，iOS 建議預設 17 pt、最小 11 pt（同上）。
- 【建議】一般避免 Ultralight、Thin、Light 字重（[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)）。
- 【建議】使用內建 text styles，搭配系統字型自動支援 Dynamic Type 與更大的無障礙字級；自訂字型必須自行實作 Dynamic Type 與 Bold Text（同上）。
- 【建議】版面要能適應所有字級；**大字級時把水平並排改成上下堆疊**、減少多欄；盡量少截斷（最大無障礙字級時顯示的有用文字量應與最大標準字級相當）；有意義的 icon 要跟著放大；維持一致的資訊層級（[Typography › Supporting Dynamic Type](https://developer.apple.com/design/human-interface-guidelines/typography#Supporting-Dynamic-Type)、[Layout › Adaptability](https://developer.apple.com/design/human-interface-guidelines/layout)）。
- 【推論】金額列表：`分類｜金額` 在無障礙字級時改上下兩行（可判斷 `dynamicTypeSize.isAccessibilitySize`）；金額用 [`monospacedDigit()`](https://developer.apple.com/documentation/swiftui/view/monospaceddigit()) 讓位數對齊（文件存在；HIG 未查到數字對齊的明文指引）；總覽大數字用 `.largeTitle` 等 text style，不寫死 pt 值。

### 3.2 Color、Dark Mode、Increase Contrast

- 【建議】同一顏色不要代表不同意義；所有顏色都要在 light、dark、increased contrast 下可用；自訂顏色要提供 light／dark 變體，**各自再加 increased contrast 變體**；即使 app 只出一種外觀，也要同時提供深淺色以支援 Liquid Glass 的適應（[Color › Best practices](https://developer.apple.com/design/human-interface-guidelines/color)）。
- 【建議】不要寫死系統色色值，用 `Color` 等 API；使用 dynamic system colors，**不要改變其語意**（例如不要把 separator 色拿來當文字色）（[Color › System colors](https://developer.apple.com/design/human-interface-guidelines/color#System-colors)）。
- 【建議】不要只靠顏色區分物件、表示互動或傳達重要資訊；**考慮顏色在不同國家與文化的意涵**（原文舉例：紅色在某些文化代表危險，在其他文化有正面含義）（[Color › Inclusive color](https://developer.apple.com/design/human-interface-guidelines/color#Inclusive-color)）。
- 【建議】iOS 背景色分 system 與 grouped 兩組，各有 primary／secondary／tertiary；grouped table 用 grouped 系列（[Color › iOS, iPadOS](https://developer.apple.com/design/human-interface-guidelines/color)）。
- 【建議】對比：Accessibility Inspector 採 WCAG AA —— 17 pt 以下 4.5:1、18 pt 3:1、粗體 3:1；預設達不到時，至少在 Increase Contrast 開啟時提供高對比配色（[Accessibility › Vision](https://developer.apple.com/design/human-interface-guidelines/accessibility)）。
- 【建議】Dark Mode：**不要提供 app 專屬的外觀設定**；對比不低於 4.5:1，自訂前景／背景色爭取 7:1；優先用系統背景色（Dark Mode 有 base／elevated 兩組，前景 sheet 會自動變 elevated）；要在 Increase Contrast 與 Reduce Transparency 開啟（分開與同時）下測試（[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)）。
- 【推論】my-money：收入／支出／超支除了顏色，一律加正負號或「收入／支出」文字，或配一個 SF Symbol。台灣使用者對紅綠的直覺可能跟股市「紅漲綠跌」混淆，語意文字加符號最不會誤讀。web 版若有深淺色切換開關，iOS 版不要搬過來（改跟隨系統）。自訂色一律放 Asset Catalog 的 Color Set，並勾選 High Contrast 變體；程式可讀 [`colorSchemeContrast`](https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast)。

### 3.3 SF Symbols

- 【建議】符號有 monochrome、hierarchical、palette、multicolor 四種 rendering mode，使用系統色即可自動適應無障礙與 Dark Mode；檢查每個情境下的可辨識度（[SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)）。
- 【建議】通常由容器決定 outline 或 fill：iOS tab bar 偏好 fill，toolbar 用 outline（同上 › Design variants）。
- 【建議】toolbar 偏好無外框的系統符號（[Toolbars › Actions](https://developer.apple.com/design/human-interface-guidelines/toolbars)）；常見動作有標準 icon 對照表（[Icons](https://developer.apple.com/design/human-interface-guidelines/icons)）。
- 【規定】SF Symbols 的使用條款禁止把 symbols（或容易混淆的相似圖像）用在 app icon、logo 或其他商標用途（[SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)）。
- 【推論】新 symbol 與功能依系統版本提供，較新的符號在舊系統不存在（同頁原文）；deployment target 若低於 iOS 27，使用 SF Symbols 8 新符號要準備 fallback。

### 3.4 App icon（含深色與 tinted 變體）

- 【建議】iOS icon 規格：1024×1024 px、方形、分層；外觀有 **Default、dark、clear light、clear dark、tinted light、tinted dark**（[App icons › Specifications](https://developer.apple.com/design/human-interface-guidelines/app-icons)）。
- 【建議】用 Icon Composer 組合圖層，並標註 default、dark、mono 外觀；系統會套用 specular highlights、refraction、translucency 等 Liquid Glass 效果，**不要自己畫陰影、模糊、高光**；提供未遮罩的方形圖層（同上 › Layer design、Visual effects）。
- 【建議】**深色與 tinted 變體不是強制項**：「You can design app icon variants for every appearance variant, and the system automatically generates variants you don't provide」。有做的話，各外觀要保持核心特徵一致，dark icon 以 light 版為基礎（同上 › Appearances）。
- 【規定】alternate app icons 需要各自的 dark、clear、tinted 變體；所有 alternate 與變體 icon 都受 App Review 審查（同上 › Appearances 的 Note）。不能在 icon 或名稱使用其他開發者的 icon、品牌或產品名（[4.1(c)](https://developer.apple.com/app-store/review/guidelines/#copycats)）；icon 與截圖須適合 4+ 年齡（[2.3.8](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)）；Apple 商標不可出現在 app 名稱或圖像（[Branding](https://developer.apple.com/design/human-interface-guidelines/branding)）。
- 【建議】除非品牌必要，icon 不放文字；偏好插畫、避免照片與複製 UI 元件；不要使用 Apple 硬體的複製圖（[App icons › Design](https://developer.apple.com/design/human-interface-guidelines/app-icons)）。
- 【推論】iOS 27 的 icon 渲染更銳利，Icon Composer 可預覽舊版系統外觀（[SOTU](https://developer.apple.com/videos/play/wwdc2026/102/)）；Icon Composer 2 beta 於 2026-06-08 釋出（[What's new](https://developer.apple.com/design/whats-new/)）。my-money 用 1~2 個重疊的簡單幾何（例如硬幣、帳本），不放「$」字或 app 名稱。

## 4. Layout、safe area、觸控目標

- 【建議】「Determine layout based on size classes, not device type or orientation」；考慮所有 size class 組合；size class 改變時功能不變（[Layout › Size classes](https://developer.apple.com/design/human-interface-guidelines/layout#Size-classes)）。
- 【建議】尊重系統定義的 safe area、margins 與 layout guides；safe area 確保 Dynamic Island 等硬體與系統 UI 不遮擋內容與控制項（[Layout › Guides and safe areas](https://developer.apple.com/design/human-interface-guidelines/layout)）。
- 【建議】全螢幕背景延伸到 sidebar、toolbar、tab bar 之下；必要時用 [`backgroundExtensionEffect()`](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect())（[Layout › Visual hierarchy](https://developer.apple.com/design/human-interface-guidelines/layout)）。
- 【建議】用最大與最小版面、不同 localization 和字級預覽，可在 Xcode 的 [Device Hub](https://developer.apple.com/documentation/xcode/device-hub) 上測（[Layout › Adaptability](https://developer.apple.com/design/human-interface-guidelines/layout)）。
- 【建議】**觸控目標**：iOS/iPadOS 預設控制項尺寸 44×44 pt、最小 28×28 pt；有 bezel 的元素周圍約 12 pt 間距，無 bezel 的約 24 pt（[Accessibility › Mobility](https://developer.apple.com/design/human-interface-guidelines/accessibility)）；按鈕 hit region 一般至少 44×44 pt（[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)）。
- 【建議】手機常用範圍在畫面中下方，列表列要支援滑動操作與滑動返回（[Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)）。
- 【推論】本次抓到的 Layout 頁（2026-09-09 更新）已看不到 iOS 逐機型尺寸表（2025-09 的 change log 還有新增 iPhone 17 規格的紀錄），版面不應再依機型寫死；尺寸參考改用 [Apple Design Resources](https://developer.apple.com/design/resources/)。my-money 的自訂金額鍵、分類 grid 格、日期快捷鈕（今天／昨天）都要 ≥ 44 pt。

## 5. Accessibility

### 5.1 通則與稽核

- 【建議】用 [Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector) 稽核；可在 App Store 以 Accessibility Nutrition Labels 揭露支援程度（[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)）。
- 【建議】Accessibility Nutrition Labels **目前自願填寫**，但官方說「over time, you'll be required」；要宣稱支援某功能，使用者必須能用該功能完成 app 的所有常見任務（[Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)）。
- 【建議】手勢要有替代：例如 swipe 關閉也提供按鈕；支援 Voice Control（要有恰當 label）、Full Keyboard Access、Switch Control（[Accessibility › Mobility、Speech](https://developer.apple.com/design/human-interface-guidelines/accessibility)）。
- 【建議】少用有計時自動消失的介面，偏好明確動作關閉（[Accessibility › Cognitive](https://developer.apple.com/design/human-interface-guidelines/accessibility)）。
- 【建議】Assistive Access 模式下，難以復原的動作（例如刪除）要確認兩次（同上）。

### 5.2 VoiceOver

- 【建議】所有關鍵元素都要有 accessibility label，自訂元素一定要加；描述有意義的圖片、排除純裝飾圖（[VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)）。
- 【建議】「Make charts and other infographics fully accessible」；用標題與 heading 幫助導覽；說明元素的分組與順序；內容或版面改變時通知 VoiceOver；支援 rotor（同上）。
- 【推論】自訂控制項要補齊 label、value、trait 與 custom actions；例如自訂滑桿要加 `.adjustable` trait（[WWDC26 Refine accessibility for custom controls](https://developer.apple.com/videos/play/wwdc2026/220/)）。my-money 若自刻金額鍵盤或預算滑桿，要走這一套。

### 5.3 Dynamic Type、Reduce Motion、Reduce Transparency、Increase Contrast

- Dynamic Type 見 §3.1。
- 【建議】Reduce Motion 開啟時，減少自動與重複的動畫（縮放、周邊移動等）；做法包括收緊 spring、動畫直接跟手勢走、避免 z 軸深度動畫、改用淡入淡出、避免進出模糊的動畫（[Accessibility › Cognitive](https://developer.apple.com/design/human-interface-guidelines/accessibility)）。動態要可選、可被取消，不能是傳達重要資訊的唯一方式（[Motion](https://developer.apple.com/design/human-interface-guidelines/motion)）。
- 【建議】Reduce Transparency／Increase Contrast：標準元件的 Liquid Glass 會自動調整；自訂元素、顏色、動畫要在各種設定組合下測試（[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)）。
- 【推論】自訂材質與動畫讀 [`accessibilityReduceTransparency`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)、[`accessibilityReduceMotion`](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)；預算達成、儲蓄目標完成的慶祝動畫，在 Reduce Motion 下改成淡入加文字。

### 5.4 數字與圖表的無障礙

- 【建議】圖表的 accessibility label：清楚完整、附上下文（日期等）；**不要用主觀詞**（rapidly、almost），用實際數值；避免模稜兩可的格式與縮寫（用「June 6」不用「6/6」）；描述資料代表什麼，而不是顏色長什麼樣；提到座標軸時順序要一致；把可見的軸與刻度文字對輔助技術隱藏（[Charts › Enhancing the accessibility of a chart](https://developer.apple.com/design/human-interface-guidelines/charts#Enhancing-the-accessibility-of-a-chart)）。
- 【建議】Swift Charts 預設為每個 mark 提供 accessibility element，並內建 [Audio graphs](https://developer.apple.com/documentation/accessibility/audio-graphs)；可自訂 chart 標題與摘要；不用 Audio Graphs 時要自行說明圖表類型、各軸代表什麼、上下界（同上）。
- 【推論】金額的 VoiceOver 文字一律由 FormatStyle 產生，並把正負號轉成語意（「支出 1,250 元」「收入 32,000 元」），不要讓 VoiceOver 念「減號」。圖表單根長條的 label 例如「9 月 6 日，支出 1,250 元」。自訂繪製的圖表用 [`accessibilityChartDescriptor(_:)`](https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor(_:))。

## 6. 輸入：金額、text field、picker、date picker、表單

- 【建議】text field 用於少量資訊，大量文字用 text view；placeholder 輸入後就消失，建議另保留 label；**敏感資料（如密碼）一律用 secure text field**（[Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields)）。
- 【建議】「Use a number formatter to help with numeric data」：formatter 可限制只收數字，並以小數位、百分比或**貨幣**格式顯示；不要假設呈現方式，格式會隨 locale 大幅不同（同上）。
- 【建議】依情境驗證：email 在切換欄位時驗證，使用者名稱／密碼在離開欄位前驗證（同上）；即時驗證、盡早回饋；必填沒填完就不要讓 Next／Continue 可按（[Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data)）。
- 【建議】顯示對應內容的鍵盤（Decimal pad、Number pad、Email address 等）；設定 `textContentType` 讓系統提供對應鍵盤與修正；可自訂 Return 鍵（`submitLabel`）（[Virtual keyboards](https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards)、[keyboardType(_:)](https://developer.apple.com/documentation/swiftui/view/keyboardtype(_:))）。
- 【建議】鍵盤上方的自訂控制要與當前任務相關；用標準 toolbar 承載會自動套 Liquid Glass；用 keyboard layout guide 讓重要介面在鍵盤出現時仍可見（[Virtual keyboards › iOS, iPadOS](https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards)）。
- 【建議】能讓人選就不要叫人打字；可預填合理預設值；**永遠不要預填密碼欄**（[Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data)、[Text fields › iOS](https://developer.apple.com/design/human-interface-guidelines/text-fields)）。
- 【建議】picker 適合中長清單；短清單用 pull-down button，很長的清單用 list；值要可預測、有邏輯順序；在欄位附近顯示，不要為了 picker 切換畫面（[Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers)）。
- 【建議】date picker 有 compact、inline、wheels、automatic 四種樣式與 date／time／date and time／countdown 四種模式；**顯示的值與順序依裝置語言與地區而定**；空間有限時用 compact；分鐘間隔可設成 60 的因數（同上 › iOS, iPadOS）。
- 【建議】segmented control：iPhone 上約 5 段以內；段落寬度一致；同一個控制項不要混用文字和圖片；label 用名詞（[Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)）。
- 【建議】表單用 SwiftUI `Form` 的 grouped 樣式，可自動取得各平台的版面規格（[Adopting Liquid Glass › Organization and layout](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)）。
- 【建議】Apple 文件：貨幣請用 `Decimal`，不要用 `Float`／`Double`；以 `Decimal.FormatStyle.Currency` 格式化（[Preparing dates, currencies, and numbers for translation](https://developer.apple.com/documentation/xcode/preparing-dates-numbers-with-formatters)）。`TextField` 可用 `value:format:` 直接綁非字串型別（[TextField](https://developer.apple.com/documentation/swiftui/textfield)）。
- 【推論】my-money 新增交易表單：
  - 金額：`TextField(value: $amount /* Decimal */, format: .currency(code: "TWD").precision(.fractionLength(0)))` 搭配 `.keyboardType(.numberPad)`；若日後支援外幣小數再改 `.decimalPad`。收入／支出用 2 段 segmented control 切換，不要讓使用者輸入負號。number pad 沒有 Return 鍵（本次未在文件中查證），用鍵盤上方的標準 toolbar 放「完成」。
  - 分類：常用分類做成 ≥ 44 pt 的 grid 或 list（能選就不要打字）；分類多時用 `Picker` 的 navigationLink 樣式。
  - 日期：`DatePicker` compact、date-only，預設今天。
  - 公帳／私帳：2 段 segmented control 或 `Picker`。
  - 備註：短就用 `TextField(axis: .vertical)`，長則用 text view。
  - 註冊／登入：`textContentType(.emailAddress)`、`.password`／`.newPassword`，並設定 associated domains 讓 Password AutoFill 與 web 版共用憑證（[Password AutoFill](https://developer.apple.com/documentation/security/password-autofill)）。

## 7. 列表、sheet、modality、alert、破壞性動作、undo

### 7.1 Lists

- 【建議】文字內容偏好 list／table；合理時讓人編輯（重新排序等）；選取回饋依導覽或切換狀態而不同；列文字精簡；iOS 用 grouped 樣式呈現分組；要鑽入下一層用 disclosure indicator，info button 只用來顯示更多資訊（[Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)）。
- 【建議】context menu 最上方的動作要與同一項目的 swipe actions 一致（[Adopting Liquid Glass › Menus and toolbars](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)）。
- 【建議】list 不再全大寫顯示 section header，改用 title-style capitalization（同上）。
- 【推論】交易列：左滑「刪除」（destructive）、右滑「編輯」或「複製為新交易」；長按 context menu 放同一組動作，並提供不靠手勢的路徑（§5.1）。

### 7.2 Sheets 與 modality

- 【建議】sheet 用於和目前情境密切相關的限定任務；複雜或冗長的流程考慮其他形式（例如全螢幕 modal）（[Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)）。
- 【建議】**從主介面一次只顯示一個 sheet**；sheet 裡觸發另一個 sheet 時，先關掉第一個（同上）。
- 【建議】iOS 單一畫面的 sheet：Cancel 在 top toolbar 的 leading，Done 在 trailing；有 Done 就必須搭配 Cancel（或多步驟流程的 Back）；Cancel、Done、Back 三個不要同時出現（同上，2026-03-24 更新按鈕位置指引）。
- 【建議】iPhone 可考慮 medium detent 做漸進揭露，但內容需要全高時（例如 Mail 撰寫）就不要；可縮放的 sheet 要有 grabber；**支援下滑關閉，有未儲存變更時用 action sheet 讓人確認**（同上 › iOS, iPadOS）。
- 【建議】只在有明確好處時使用 modal；保持簡短；不要在 modal 裡做出「app 中的 app」，若 modal 內需要子畫面，只提供單一路徑；永遠提供明顯的關閉方式；關閉會遺失使用者內容時先確認；不要同時顯示多個 modal（[Modality](https://developer.apple.com/design/human-interface-guidelines/modality)）。
- 【推論】新增／編輯交易 sheet 只用 large detent（表單加鍵盤需要全高），用 `interactiveDismissDisabled(hasChanges)` 加 `confirmationDialog` 做「捨棄變更／繼續編輯」（[interactiveDismissDisabled(_:)](https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:))、[confirmationDialog](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:))）。在 sheet 內新增分類，用 sheet 內的 `NavigationStack` push，不要再疊第二個 sheet。

### 7.3 Alerts、action sheets、按鈕角色

- 【建議】alert 要節制；不要只為了告知資訊就跳 alert；**常見、可復原的動作即使是破壞性的也不要跳 alert**；少見且不可復原的破壞性動作才跳；**不要在 app 啟動時跳 alert**（例如無網路改顯示快取資料加不打擾的標示）（[Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)）。
- 【建議】標題要具體描述狀況，不要只寫「Error」或錯誤碼；按鈕用一兩個字的動詞，非純告知的 alert 避免用「OK」當預設按鈕；取消一律叫「Cancel」且不設為預設按鈕；destructive 樣式用在使用者**非刻意**選擇的破壞性動作；有破壞性動作時一定附 Cancel（同上）。
- 【建議】iOS：對使用者刻意發起的動作提供後續選擇時，用 action sheet 而不是 alert（同上 › iOS, iPadOS）。
- 【建議】action sheet 節制使用；destructive 選項放最上方且醒目；附 Cancel；含 Cancel 在內不超過 4 個按鈕；不要讓它需要捲動；SwiftUI 用 confirmation dialog（[Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets)）。
- 【建議】不要把 primary role 指派給破壞性按鈕（[Buttons › Role](https://developer.apple.com/design/human-interface-guidelines/buttons)）。
- 【建議】只在意料之外且不可逆的資料遺失前警告；資料遺失本來就是預期結果時不用警告（[Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)）。

### 7.4 Undo

- 【建議】讓人能預測 undo 的結果（iPhone 搖一搖的 alert 會顯示描述）；顯示 undo 的結果（捲到被還原處）；允許多次 undo；不要重新定義系統的 undo 手勢（三指滑、搖動）；undo／redo 的 alert 標題系統會加「Undo」「Redo」前綴，你只要補一兩個描述字（[Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo)）。
- 【推論】my-money 破壞性動作分級（後端是否支援軟刪除、是否有「還原」endpoint，本研究未查）：

| 動作 | 性質 | 建議處理 |
|---|---|---|
| 刪除單筆交易 | 常見 | 後端能還原 → 直接刪除並提供 undo（`UndoManager`、搖一搖）；不能還原 → confirmationDialog，destructive 按鈕寫「刪除交易」 |
| 刪除銀行／信用卡帳戶（連帶交易） | 少見、不可逆、有連帶影響 | 確認對話框，標題寫明「刪除『信用卡 A』與 128 筆交易？」 |
| 刪除固定收支、儲蓄目標、預算 | 少見 | 確認，說明是否影響歷史交易 |
| 退出或解散家庭群組 | 影響其他成員 | alert，寫明對公帳資料的影響 |
| 解除 LINE/Telegram 綁定 | 可重新綁定 | 輕量確認或直接執行加 undo |
| 刪除帳號 | 不可逆 | 重新驗證加明確說明，見 §9.4 |

## 8. Charts（HIG 與 Swift Charts）

- 【建議】圖表用來凸顯資料的重點；只是要提供資料、不需分析時，改用可捲動、搜尋、排序的 list（[Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)）。
- 【建議】保持簡單，讓人自己選擇何時看細節；偏好常見類型（bar、line）；加描述性標題、副標與註解，摘要主要訊息；多張圖目的相似時保持風格一致，同一份資料的多張圖保持連續性（同上）。
- 【建議】mark 依要傳達的資訊選擇：bar 適合比較類別與部分佔整體，以及時間上的加總；line 適合看趨勢；line 加 point 可同時看趨勢與個別值（[Charts › Marks](https://developer.apple.com/design/human-interface-guidelines/charts)）。
- 【建議】軸：依意義選固定或動態範圍；bar chart 的 Y 軸下界通常用 0；刻度用常見數列（0、5、10）；grid line 密度配合用途（同上 › Axes）。
- 【建議】compact 環境盡量加寬繪圖區、縮短垂直軸 label、把單位寫在標題；互動只在合理時提供，**不能要求互動才看得到關鍵資訊**；mark 太小時把 hit target 擴大到整個繪圖區讓人 scrub；支援鍵盤與 Switch Control 的導覽路徑；圖表變化時除了動畫還要用其他方式提示（同上 › Best practices）。
- 【建議】不要只靠顏色區分資料，可加形狀或圖樣；相鄰色塊之間加分隔（同上 › Color）。
- 【建議】Swift Charts 內建 localization 與 accessibility 支援，可自動產生 scale 與 axis（[Swift Charts](https://developer.apple.com/documentation/charts)）；圓餅／甜甜圈圖用 [`SectorMark`](https://developer.apple.com/documentation/charts/sectormark)。
- 【推論】my-money 功能對應：

| 功能 | 建議圖型 | 重點 |
|---|---|---|
| 分類支出分析 | 依金額排序的水平 bar | 比較類別時 bar 比圓餅容易讀；若用 SectorMark，每個扇區都要有 label，不能只靠顏色 |
| 月趨勢 | bar（每月加總）| Y 軸從 0 開始 |
| 30 天現金流預測 | line；實際與預測兩段用不同線型（實線／虛線），不只靠顏色 | 餘額可能為負，Y 軸不要固定下界 0；標題寫摘要，例如「預計 10/15 餘額最低 NT$3,200」 |
| 月預算 | `ProgressView`／`Gauge` 加文字 | 超支用文字加 icon，不只變紅 |
| 「這筆買得起嗎」 | 以文字結論為主，圖為輔 | 關鍵結論不能藏在互動後 |

## 9. Onboarding、登入、帳號管理、帳號刪除

### 9.1 Onboarding 與啟動

- 【建議】onboarding 要快、有趣、可略過；在啟動完成後才出現；透過實際操作教學；偏好情境式小提示（[TipKit](https://developer.apple.com/documentation/tipkit)）而非一整段流程；可選的教學略過後不要每次再出現；延後非必要的設定；隱私權限在使用對應功能時才詢問；不要在 onboarding 放授權條款（[Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)）。
- 【建議】launch screen 要幾乎和第一個畫面一樣、不放文字、不做品牌宣傳；重新啟動時恢復先前狀態（[Launching](https://developer.apple.com/design/human-interface-guidelines/launching)）。
- 【建議】「Ask people to create an account only if your core functionality requires it」；在登入畫面簡短說明為什麼需要帳號與好處；盡量延後要求登入（[Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)）。
- 【規定】沒有重要的帳號相關功能時，要讓人不登入就能使用（[5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)）。
- 【推論】my-money 的資料都在伺服器、需要跟 web 版與家庭成員同步，屬於「significant account-based features」，要求登入合理。登入頁用一句話說明「與網頁版同步、家庭共用帳本」；首次登入後用 TipKit 提示「新增第一筆交易」，不做多頁導覽。

### 9.2 Sign in 與 Sign in with Apple（對照 4.8）

- 【規定】4.8 條件：使用第三方或社群登入服務（原文舉例 Facebook、Google、X、LinkedIn、Amazon、WeChat）**來設定或驗證使用者的主要帳號**時，必須另外提供一個等價登入選項，且該服務要：只收集姓名與 email、允許隱藏 email、未經同意不收集 app 內互動做廣告用途。以下情況不需要另外提供：**「Your app exclusively uses your company's own account setup and sign-in systems」**、教育或企業帳號、政府 eID、特定第三方服務的 client 等（[4.8 Login Services](https://developer.apple.com/app-store/review/guidelines/#login-services)）。
- 【推論】my-money 目前只有自家 email／密碼（JWT），**4.8 不適用，不需要 Sign in with Apple**。LINE/Telegram 是綁定 bot 以接收或記錄交易，不是設定或驗證主帳號，也不觸發 4.8。日後若加入「用 LINE／Google 登入」，就必須同時提供一個符合三項條件的登入選項（Sign in with Apple 是常見選擇；它是否滿足三項條件是依 HIG 描述推論：「Apple doesn't use Sign in with Apple to profile people or their activity in apps」，見 [Sign in with Apple](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)）。
- 【建議】若要求帳號，可考慮 Sign in with Apple；若不用 Sign in with Apple，偏好 passkey；仍用密碼時，**要求雙因素驗證**以加強安全（[Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)、[Privacy › Protecting data](https://developer.apple.com/design/human-interface-guidelines/privacy#Protecting-data)）。避免自創驗證機制，偏好 passkeys、Sign in with Apple 或 Password AutoFill（同上）。
- 【推論】passkey 與 2FA 都需要後端（Hono/Workers）配合，屬中期工作；第一版至少做到 Password AutoFill（associated domains）。若日後採用 Sign in with Apple，要注意 Apple 已公告新的 relay email 網域 `private.icloud.com`，驗證邏輯需同時接受新舊網域（[News 2026-08-24](https://developer.apple.com/news/?id=1ptvdtcm)）。

### 9.3 帳號管理（HIG）

- 【建議】明確標示驗證方式（例如「使用 Face ID 登入」而不是「登入」）；只提到目前裝置可用的方式（用 [`LABiometryType`](https://developer.apple.com/documentation/localauthentication/labiometrytype) 判斷）；**一般避免在 app 內提供「開啟生物辨識」的設定**（系統層已有）；不要用「passcode」指稱帳號驗證（[Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)）。
- 【建議】尊重系統設定，不要在 app 設定裡重複全域選項（無障礙、驗證方式等）；app 設定放一般、不常變更的選項，例如帳號相關設定（[Settings](https://developer.apple.com/design/human-interface-guidelines/settings)）。
- 【推論】中文 UI 的帳號密碼只能叫「密碼」，但不要出現「裝置密碼」「解鎖密碼」這類會讓人以為要重用手機密碼的字眼。

### 9.4 帳號刪除要求與後端缺口

**Apple 原文**

- 【規定】「If your app supports account creation, you must also offer account deletion within the app」（[5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)）。
- 【規定】要能刪除**整筆帳號紀錄與相關個資**，只提供暫時停用或關閉是不夠的；選項要好找（通常在帳號設定）；如果需要到網站完成，**直接連到可完成刪除的那一頁**；若要花時間，要告知使用者（[Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/)）。
- 【規定】FAQ（同頁）：
  - 非 5.1.1(ix) 所列高度監管產業的 app，「should not require people to make a phone call, send an email, or go through other support flows」。
  - 可以要求重新驗證或加確認步驟，但刻意設難的會被退件。
  - 以瀏覽器外連建立帳號的 app 仍須在 app 內提供刪除（而且外連登入／註冊本身就被視為不當）。
  - 刪除可以是人工、非即時的，但要告知需要多久，並在完成時通知。
  - 分享給他人的使用者內容也要一併刪除；法規要求保留的資料要告知使用者。
  - 只在 GDPR／CCPA 等地區提供刪除不夠，所有地區的使用者都要能刪除。
- 【建議】app 內無法完成時，要提供直達刪除網頁的連結，不要藏在隱私權政策或服務條款裡；app 與網站的刪除流程要一致；可以提供排程刪除，但也要能立即刪除；告知何時完成、完成時通知（[Managing accounts › Deleting accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)）。
- 【規定】隱私權政策要說明資料保留與刪除政策，以及使用者如何撤回同意或要求刪除（[5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)）。

**對 my-money 的影響（【推論】）**

| 方案 | 合規？ | 說明 |
|---|---|---|
| 維持現狀（沒有刪除功能） | 否 | iOS 版有註冊功能即觸發 5.1.1(v)；送審前必須解決 |
| app 內按鈕改成寄 email 或聯絡客服 | 否 | FAQ 明說非監管產業不應要求 email 或客服流程 |
| 只做「停用帳號」 | 否 | 支援頁明說只停用不夠 |
| 後端新增「刪除請求」endpoint，app 內發起、後台非同步或人工處理 | 是 | FAQ 允許人工且非即時，但 app 要顯示預計完成時間，並在完成時通知（例如 email） |
| 後端新增即時刪除 endpoint（建議） | 是 | 最單純；可要求重新輸入密碼 |
| web 版做刪除頁，app 內直連 | 是 | web 版目前同樣缺 endpoint，一樣要開發後端；兩邊流程要一致 |

- 【推論】刪除範圍要先定義清楚：帳號與個資、該使用者所有私帳資料、該使用者在家庭群組建立的公帳交易（FAQ：分享給他人的內容也要刪）、家庭群組擁有權轉移或解散規則、邀請碼失效、LINE/Telegram 綁定解除、所有 JWT refresh token 撤銷。建議刪除前先提供 CSV 匯出入口（不是 Apple 要求）。
- 【推論】排程影響：後端 endpoint 是 **App Store 送審的前置條件**。TestFlight 外部測試的第一個 build 也要經 App Review（[TestFlight](https://developer.apple.com/testflight/)），而 2.2 說 TestFlight 版本也應符合 Review Guidelines（[2.2](https://developer.apple.com/app-store/review/guidelines/#beta-testing)）；內部測試是否受影響，頁面沒說（未查證）。如果短期只給家人用，可用 Xcode 直接安裝或 Ad Hoc（見結論 15）。

## 10. Privacy 與安全

### 10.1 隱私權政策、同意與第三方分享

- 【規定】ASC 與 app 內都要有容易找到的隱私權政策連結；政策要寫清楚收集哪些資料、如何收集、所有用途；第三方要提供同等保護；保留與刪除政策（[5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)）。
- 【規定】收集使用者或使用資料要取得同意，並提供容易撤回同意的方式；purpose string 要清楚完整（[5.1.1(ii)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)）；只要求與核心功能相關的資料（[5.1.1(iii)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)）。
- 【規定】沒有許可不得使用、傳輸或分享個資；**分享給第三方（包含第三方 AI）要清楚揭露並先取得明確許可**；追蹤要透過 ATT；不能要求開啟推播、定位、追蹤才能使用 app（[5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing)）。
- 【規定】app 必須提供機制，讓使用者能在 app 內撤銷社群網路憑證、停止 app 與社群網路間的資料存取；社群網路的憑證或 token 不得存在裝置以外（[5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)，此段是針對社群網路登入的語境）。
- 【推論】LINE/Telegram 綁定後，交易資料會經過這兩個平台，屬於「分享給第三方」：綁定前的畫面要說明哪些資料會送到 LINE/Telegram，並取得明確同意；app 內要能解除綁定。後端若保存 LINE Login 的 access token（不只是 user ID），要重新檢視是否違反「token 不得存在裝置外」（此段是否適用 bot 綁定，Apple 未明說，屬保守解讀）。

### 10.2 App Privacy 標示（Privacy Nutrition Label）

- 【規定】送出新 app 或更新時，必須在 App Store Connect 提供隱私作法與收集的資料類型（[HIG Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)）；metadata（含隱私資訊）要正確並保持更新（[2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)）。
- 【規定】要列出你與第三方夥伴收集的所有資料，除非同時符合所有「選擇性揭露」條件；「collect」指把資料傳離裝置、且保存超過即時處理請求所需的時間（[App privacy details](https://developer.apple.com/app-store/app-privacy-details/)）。
- 【推論】my-money 可能要揭露的類型（依該頁的類型定義）：Contact Info › **Email Address**（以及 Name，若有）；Identifiers › **User ID**；Financial Info › **Other Financial Info**（原文「salary, income, assets, debts, or any other financial information」）；若存完整銀行帳號或卡號則屬 **Payment Info**（原文列有 bank account number，建議只存帳戶暱稱或末四碼）；Purchases › **Purchase History**（原文「purchases or purchase tendencies」，支出紀錄可能屬之，建議保守揭露）。用途：App Functionality；Linked to user：是；Tracking：否。該頁對「third-party partners」的定義是加進 app 的第三方程式碼（analytics、廣告網路、SDK 等），代管後端 Cloudflare 是否算進來，頁面沒有直接說明（未查證）。

### 10.3 Privacy manifest

- 【規定·技術】app 或第三方 SDK 可以附 `PrivacyInfo.xcprivacy`，記錄收集的資料類型（所有平台）與使用的 required reason API（iOS 等平台）；頂層 key 為 `NSPrivacyTracking`、`NSPrivacyTrackingDomains`、`NSPrivacyCollectedDataTypes`、`NSPrivacyAccessedAPITypes`（[Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)）。
- 【規定·技術】「Starting May 1, 2024, apps that don't describe their use of required reason API in their privacy manifest file aren't accepted by App Store Connect」；只能依申報的理由使用，也不得用於追蹤（[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)）。
- 【規定·技術】required reason API 分類包括 `UserDefaults`、File timestamp、System boot time、Disk space、Active keyboards；`UserDefaults` 的理由碼：`CA92.1`（只存取 app 自己的資料）、`1C8F.1`（同一個 App Group 的 app／extension）（[NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)）。
- 【推論】SwiftUI 的 `@AppStorage` 底層是 `UserDefaults`，my-money 幾乎一定要申報 `CA92.1`；如果 widget 透過 App Group 共用設定，再加 `1C8F.1`。`NSPrivacyCollectedDataTypes` 內容要跟 ASC 的 App Privacy 標示一致。不引入第三方 analytics SDK，可以大幅簡化 manifest 與標示。

### 10.4 Face ID／Touch ID 鎖定 app

- 【建議】「To further protect access to apps that people keep logged in on their device, use biometric identification like Face ID, Optic ID, or Touch ID」（[Privacy › Protecting data](https://developer.apple.com/design/human-interface-guidelines/privacy#Protecting-data)）。
- 【建議】按鈕要寫明驗證方式（「使用 Face ID 解鎖」）；只提目前裝置有的方式；一般避免在 app 內提供生物辨識的 opt-in 設定（[Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)）。
- 【規定·技術】使用 Face ID 的 app 必須在 Info.plist 設 `NSFaceIDUsageDescription`，否則系統不允許使用 Face ID；Touch ID 不需要（[NSFaceIDUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsfaceidusagedescription)、[Logging a User into Your App with Face ID or Touch ID](https://developer.apple.com/documentation/localauthentication/logging-a-user-into-your-app-with-face-id-or-touch-id)）。
- 【規定】以臉部辨識做帳號驗證時，能用 LocalAuthentication 就必須用它（不可用 ARKit 或其他臉部辨識技術），而且要替 13 歲以下使用者提供替代驗證方式（[2.5.13](https://developer.apple.com/app-store/review/guidelines/#software-requirements)）。
- 【建議】Apple 文件：先用 `canEvaluatePolicy` 檢查可用性；`.deviceOwnerAuthentication` 允許在生物辨識失敗時退回裝置密碼，`.deviceOwnerAuthenticationWithBiometrics` 則不允許；提供退回自家帳密的路徑（同上文件）。
- 【推論】HIG 在這裡有張力：Privacy 頁鼓勵用生物辨識保護常駐登入的 app，Managing accounts 頁卻建議避免 app 專屬的生物辨識 opt-in 設定。折衷做法：把功能包裝成隱私功能「App 鎖定」（離開 app 超過 N 分鐘需解鎖），而不是「開啟 Face ID 登入」；使用 `.deviceOwnerAuthentication`，讓沒有生物辨識或辨識失敗的人能用裝置密碼。

### 10.5 Keychain 存 token 與背景快照

- 【建議】「Store sensitive information in a keychain」；「Never store passwords or other secure content in plain-text files」（[Privacy › Protecting data](https://developer.apple.com/design/human-interface-guidelines/privacy#Protecting-data)）。
- 【建議】Keychain 可用 `kSecAttrAccessible` 依裝置狀態控制存取；**用對 app 來說最嚴格且可行的選項**；結尾是 `ThisDeviceOnly` 的值不會遷移到其他裝置；需要在背景存取時用 After First Unlock；Always 不建議。可用 `SecAccessControl` 加 `.userPresence` 在取出憑證前再確認使用者本人（原文舉例：直接控制銀行帳戶的 app）（[Restricting keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)）。
- 【建議】（文件措辭是 must，但不是審核條款）app 進入背景後系統會截圖給 app switcher 用：「Your app's UI must not contain any sensitive user information, such as passwords or credit card numbers」，進背景前移除敏感內容（[Preparing your UI to run in the background](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background)）。
- 【規定】app 應實作適當的安全措施，防止使用者資訊被未授權使用、揭露或存取（[1.6 Data Security](https://developer.apple.com/app-store/review/guidelines/#data-security)）。
- 【推論】JWT access／refresh token 存 Keychain：只在前景使用時用 [`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)；widget 或背景刷新需要時用 [`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)，並透過 keychain access group 共用。token 不放 `UserDefaults` 或 `@AppStorage`。`scenePhase` 變成 `.inactive` 時蓋上隱私遮罩（金額模糊或 logo 畫面）。

## 11. 金融類 app 的特別條款

- 【規定，部分軟性】「Apps used for financial trading, investing, or money management should be submitted by the financial institution performing such services and must have necessary licensing and permissions in the locations where you make them available」（[3.2.1(viii)](https://developer.apple.com/app-store/review/guidelines/#acceptable)）。
- 【規定，軟性】「Apps that provide services in highly regulated fields (such as banking and financial services, healthcare, gambling, legal cannabis use, air travel and crypto exchanges) or that require sensitive user information should be submitted by a legal entity that provides the services, and not by an individual developer」（[5.1.1(ix)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)）。
- 【規定】個人貸款 app 的揭露與 APR 上限等規定（[3.2.2(ix)](https://developer.apple.com/app-store/review/guidelines/#unacceptable)）：my-money 不提供貸款，不適用。
- 【規定】截圖與預覽要用虛構帳戶資訊，不能用真人資料（[2.3.9](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)）；截圖要顯示 app 使用中的畫面，不能只是標題、登入頁或 splash（[2.3.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)）。
- 【規定】App Privacy 有「Regulated Financial Services Disclosure」的選擇性揭露例外，但前提是 app 協助受監管的金融服務，且符合所有條件（[App privacy details](https://developer.apple.com/app-store/app-privacy-details/)）。【推論】my-money 不適用，照一般規則揭露。
- 【推論】my-money 是使用者手動記錄收支、不連銀行 API、不經手或移轉資金、不提供投資交易，研判不屬於「金融機構提供的 money management 服務」或「banking and financial services」。但 Apple 沒有定義「money management」（未查證），以個人開發者帳號提交有被質疑的風險。處理方式：在 App Review notes 寫明「僅供使用者自行記錄、不連接任何金融機構、不移轉資金、不提供投資或借貸服務」；app 名稱與說明避免「銀行」「理財顧問」等字眼。30 天預測與「這筆買得起嗎」加註「依你輸入的資料估算，非財務建議」（這點本次**未查到 Apple 相關條款**，是一般風險控管）。

## 12. 通知與 widgets

### 12.1 Notifications

- 【規定】推播不得成為 app 運作的必要條件，且「should not be used to send sensitive personal or confidential information」；促銷或直接行銷需要使用者在 app UI 中明確同意，並提供退出方式（[4.5.4](https://developer.apple.com/app-store/review/guidelines/#apple-sites-and-services)）。不能用推播發送垃圾、釣魚或不請自來的訊息（4.5.3，同上）。
- 【規定】不能要求使用者開啟推播才能使用功能（[5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing)）；widget、extension、通知要與 app 的內容和功能相關（[2.5.16](https://developer.apple.com/app-store/review/guidelines/#software-requirements)）。
- 【建議】送任何通知前都要取得許可（[Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)、[Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)）；在使用者用到相關功能時才請求（[Privacy › Requesting permission](https://developer.apple.com/design/human-interface-guidelines/privacy#Requesting-permission)）。
- 【建議】通知要簡潔；同一件事不要重複發；不要用通知叫人去 app 裡做事；錯誤訊息用 alert 而不是通知；**不要在通知裡放敏感、個人或機密資訊**；使用者隱藏預覽時，提供概括性的替代文字（`hiddenPreviewsBodyPlaceholder`）；app 在前景時低調呈現（[Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications)）。
- 【建議】badge 只用來顯示未讀通知數量，**不要用 badge 顯示其他數字資訊**（原文舉例股價、天氣）（同上 › Badging）。
- 【建議】為每則通知選擇實際的 interruption level：Time Sensitive 只用於正在發生或一小時內會發生的事，絕不用在行銷；行銷通知要先取得明確同意，並在 app 內提供可更改選擇的設定畫面（[Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)）。
- 【推論】my-money：固定收支到期提醒用本機通知、Active 等級；預算超支用 Active，不用 Time Sensitive；通知內文預設不放金額（例如「本月餐飲預算已超過」），金額進 app 再看；badge 不拿來顯示剩餘預算；已經綁定 LINE/Telegram bot 的使用者，同一事件不要 app 推播和 bot 各發一次。

### 12.2 Widgets

- 【建議】widget 顯示即時、一眼可讀的內容；平衡資訊密度；點擊要深度連結到相關位置；互動元件要少、避免做成 app 般的版面；多數 widget 用標準 16 pt 邊距；用系統字型、text styles、SF Symbols；更新頻率有限，**不要把舊資料藏在 placeholder 後面**；Lock Screen widget 要提供有用資訊，不只是啟動 app 的入口；支援 Always-On 與 StandBy（[Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets)）。
- 【建議】WidgetKit：widget 高度可見（尤其是 Always-On），用 [`privacySensitive(_:)`](https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:)) 標記敏感內容，使用者可設定鎖定時是否顯示；整個 widget 都敏感時，可以開 Data Protection capability，讓裝置解鎖前只顯示 placeholder（[Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)）。
- 【推論】my-money：small「本月剩餘預算」、medium「30 天現金流迷你折線」；金額加 `privacySensitive()`；Lock Screen 版考慮 Data Protection；可放一個「記一筆」按鈕，用 App Intent 開啟 app 的新增交易 sheet。widget 與主 app 共用資料會用到 App Group，privacy manifest 要加 `1C8F.1`（§10.3）。

## 13. Localization：zh-Hant-TW 的數字、貨幣、日期

- 【建議】版面要處理依 locale 而變的國際化項目，包括日期、時間、數字格式與文字長度（[Layout › Adaptability](https://developer.apple.com/design/human-interface-guidelines/layout)）；數字欄位不要假設呈現方式（[Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields)）；date picker 的值與順序依裝置語言與地區而定（[Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers)）。
- 【建議】Apple 文件：用 Foundation 內建 formatter 與 FormatStyle 產生依裝置 locale 的字串；貨幣先查 ISO 4217 代碼，再用 `Decimal.FormatStyle.Currency(code:locale:)`；貨幣用 `Decimal`，不要用 `Float`／`Double`；機器可讀的日期可用 `.iso8601`（[Preparing dates, currencies, and numbers for translation](https://developer.apple.com/documentation/xcode/preparing-dates-numbers-with-formatters)、[Data Formatting](https://developer.apple.com/documentation/foundation/data-formatting)）。
- 【建議】字串用 String Catalog 管理；在 Xcode preview 與模擬器用各語言測試；上架時在 App Store Connect 本地化 app 資訊；需要較多垂直空間的語言用 Dynamic Type 避免裁切（[Localization](https://developer.apple.com/documentation/xcode/localization)、[Supporting multiple languages in your app](https://developer.apple.com/documentation/xcode/supporting-multiple-languages-in-your-app)、[Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)）。
- 【推論】本機實測（macOS 26.5.2 Foundation，locale `zh_Hant_TW`、時區 Asia/Taipei；**iOS 27 未實測**）：

| 呼叫 | 輸出 |
|---|---|
| `12345.67.formatted(.currency(code: "TWD"))` | `$12,345.67` |
| 同上，負值 | `-$12,345.67` |
| 加 `.precision(.fractionLength(0))` | `$12,346` |
| `.presentation(.isoCode)` | `TWD 12,345.67` |
| `Locale.currency` | `TWD` |
| `Date.FormatStyle(date: .abbreviated, time: .shortened)` | `2026年9月28日 下午5:05` |
| `date: .numeric` | `2026/9/28` |
| `.dateTime.year().month().day().weekday()` | `2026年9月28日週一` |
| `Calendar(identifier: .republicOfChina)` 的年份 | `115` |

- 【推論】由此歸納：
  1. TWD 預設帶兩位小數，而且符號是 `$`。若後端以整數元儲存，所有顯示處都要明確 `precision(.fractionLength(0))`；家庭成員若有外幣帳戶，`$` 會與 USD 混淆，可考慮 `.isoCode` 或自行加「NT」。
  2. 顯示用 locale 感知的 FormatStyle，**傳輸與儲存**用 ISO 8601 加固定 gregorian 曆，避免使用者把行事曆改成民國曆後送出 `115-09-28`。
  3. 交易「日期」是日曆日，在 Asia/Taipei 時區做 date-only 處理，避免經 UTC 轉換後跨日。
  4. 千分位是逗號、小數點是句點（實測輸出）；金額輸入欄用 `TextField(value:format:)` 讓 formatter 處理，不要自己解析字串。

## 14. 其他上架硬性要求（與本 app 相關）

- 【規定】送審版本要是完整的最終版：沒有 placeholder、網址都能用、上架前在實機測過；有登入的要附 demo 帳號**並開著後端**；會崩潰或有明顯技術問題的 binary 會被拒（[2.1(a)](https://developer.apple.com/app-store/review/guidelines/#app-completeness)）。非顯而易見的功能要在 App Review notes 詳細說明（[Before You Submit](https://developer.apple.com/app-store/review/guidelines/#before-you-submit)）；不能有隱藏或未說明的功能（[2.3.1(a)](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)）。
- 【規定】年齡分級問卷要據實作答（[2.3.6](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)）；2026 年 9 月起，送新 app 或更新都必須回答新的社群媒體能力問題（[News 2026-07-09](https://developer.apple.com/news/?id=tlur8uvi)）。【推論】家庭群組不是公開 feed，一般不算社群媒體能力，仍需依定義作答。
- 【規定】只能用公開 API，且必須能在目前發行的 OS 上執行（[2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)）；在純 IPv6 網路下要完全可用（[2.5.5](https://developer.apple.com/app-store/review/guidelines/#software-requirements)）。
- 【規定】app 要比「重新包裝的網站」提供更多功能與 app 體驗（[4.2](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality)）；要能獨立運作，不依賴安裝其他 app（[4.2.3(i)](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality)）。【推論】原生 SwiftUI 沒有 4.2 疑慮；LINE/Telegram 綁定是選用功能，不影響 4.2.3。
- 【規定】app 與 Support URL 都要有容易聯絡你的方式（[1.5](https://developer.apple.com/app-store/review/guidelines/#developer-information)）。
- 【規定·技術】SDK 與 deployment target：見「版本現況」表。【推論】新 app 以 Xcode 27 建置、deployment target 設 iOS 26（iOS 26 與 27 都支援 iPhone 11 以上，見 [security releases](https://support.apple.com/en-us/100100) 的支援機型欄），可用 Liquid Glass API 又不排除仍在 26.x 的使用者；若要用 iOS 27 才有的 API（例如 `TabRole.prominent`），用 `#available` 判斷。

## Apple 規定條款總表

| # | 條款 | 一句話 | 對 my-money | 連結 |
|---|---|---|---|---|
| 1 | 5.1.1(v) | 支援建立帳號就必須在 app 內提供刪除帳號 | **適用，後端缺口，blocker** | [RG](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) |
| 2 | 帳號刪除支援頁 | 要刪整筆紀錄與個資；只停用不夠；網頁完成要直連；非監管產業不得要求電話／email／客服；可人工但要告知時程與完成通知；分享內容也要刪 | 適用 | [Support](https://developer.apple.com/support/offering-account-deletion-in-your-app/) |
| 3 | 5.1.1(v) | 沒有重要帳號功能時要能免登入使用 | 有同步與家庭功能，可要求登入 | [RG](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) |
| 4 | 5.1.1(v) | 能在 app 內撤銷社群網路憑證與資料存取；社群 token 不存在裝置外 | 保守套用到 LINE/Telegram 綁定 | [RG](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) |
| 5 | 5.1.1(i) | ASC 與 app 內都要有隱私權政策，內容含保留與刪除政策 | 適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) |
| 6 | 5.1.1(ii)(iii) | 收集資料要同意並可撤回；purpose string 清楚；資料最小化 | 適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) |
| 7 | 5.1.1(ix)（軟性） | 銀行與金融服務等高度監管領域應由法人提交 | 研判不適用，但定義未明，送審說明處理 | [RG](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) |
| 8 | 5.1.2(i) | 分享個資給第三方要揭露並取得明確許可；不得要求開推播／追蹤才能用 | LINE/Telegram 綁定要取得同意 | [RG](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing) |
| 9 | 3.2.1(viii)（部分軟性） | 交易、投資、money management 類 app 應由提供服務的金融機構提交並具執照 | 研判不適用，定義未明 | [RG](https://developer.apple.com/app-store/review/guidelines/#acceptable) |
| 10 | 4.8 | 以第三方／社群登入建立主帳號時，須另提供符合三項隱私條件的登入；自有帳號系統例外 | 目前不適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#login-services) |
| 11 | 2.1(a) | 完整版本、demo 帳號、後端要開著、不能崩潰 | 適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#app-completeness) |
| 12 | 2.2 | TestFlight 版本也應符合 Review Guidelines | 外部測試會受影響 | [RG](https://developer.apple.com/app-store/review/guidelines/#beta-testing) |
| 13 | 2.3、2.3.1(a)、2.3.3、2.3.6、2.3.8、2.3.9 | metadata（含隱私資訊）正確；不能有隱藏功能；截圖要是使用中畫面；年齡分級據實；icon 與截圖適合 4+；截圖用虛構帳戶資訊 | 適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) |
| 14 | 2.5.1、2.5.5 | 只用公開 API、能在目前 OS 執行；支援純 IPv6 網路 | 適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#software-requirements) |
| 15 | 2.5.13 | 臉部辨識驗證要用 LocalAuthentication，並替 13 歲以下提供替代方式 | 做 Face ID 鎖時適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#software-requirements) |
| 16 | 2.5.16 | widget、extension、通知要與 app 內容相關 | 適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#software-requirements) |
| 17 | 4.5.3、4.5.4 | 推播不得成為必要條件、不應傳敏感資訊（軟性）、行銷需明確同意與退出；不得 spam | 適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#apple-sites-and-services) |
| 18 | 4.1(c)、4.2、4.2.3(i) | 不用他人的 icon 或品牌；要超越重新包裝的網站；能獨立運作 | 適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality) |
| 19 | 1.5、1.6 | 要提供聯絡方式與 Support URL；要有適當的資料安全措施 | 適用 | [RG](https://developer.apple.com/app-store/review/guidelines/#developer-information) |
| 20 | 2.4.1（軟性） | iPhone app 應盡量能在 iPad 執行 | 建議做 universal | [RG](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) |
| 21 | App Privacy 標示 | 送審要在 ASC 提供隱私作法與收集的資料類型 | 適用 | [HIG Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)、[App privacy details](https://developer.apple.com/app-store/app-privacy-details/) |
| 22 | Privacy manifest（技術） | required reason API 沒申報，ASC 拒收上傳 | `UserDefaults`（`CA92.1`，App Group 加 `1C8F.1`） | [Docs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) |
| 23 | `NSFaceIDUsageDescription`（技術） | 沒有這個 key 就不能用 Face ID | 做 Face ID 鎖時適用 | [Docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nsfaceidusagedescription) |
| 24 | SDK 與 deployment target（技術） | 2026-04-28 起 Xcode 26／iOS 26 SDK；2027-04 起 iOS 27 SDK；target ≥ iOS 13 | 適用 | [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)、[News](https://developer.apple.com/news/?id=k1mtkt1k) |
| 25 | `UIDesignRequiresCompatibility`（技術） | 以 iOS 27 SDK 建置時系統會忽略此 key，無法退回舊設計 | 適用 | [Docs](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility) |
| 26 | 年齡分級社群媒體問題 | 2026-09 起送審必須回答 | 適用 | [News 2026-07-09](https://developer.apple.com/news/?id=tlur8uvi) |
| 27 | SF Symbols 授權 | 不可用於 app icon、logo 或商標用途 | 做 icon 時適用 | [HIG SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols) |
| 28 | Alternate app icons | 需各自的 dark／clear／tinted 變體，且受審查 | 若提供替代 icon | [HIG App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons) |

## 未查證或不確定的項目

1. **3.2.1(viii) 的「money management」與 5.1.1(ix) 的「banking and financial services」是否涵蓋手動記帳 app**：Apple 沒有定義，也沒查到官方 FAQ；本文件的「研判不適用」是推論。
2. **iOS 版若只提供登入、不提供註冊，5.1.1(v) 是否仍適用**：條文以「supports account creation」為條件，FAQ 只涵蓋外連瀏覽器註冊的情況（答案是仍要提供）；只有登入的情況沒有直接說明，不建議依賴這個灰色地帶。
3. **TestFlight 內部測試是否受 App Review 或帳號刪除要求影響**：[TestFlight](https://developer.apple.com/testflight/) 頁只說外部測試要審核。
4. **zh_Hant_TW 貨幣與日期格式**：只在 macOS 26.5.2 實測，iOS 27 的實際輸出未驗證。
5. **number pad／decimal pad 沒有 Return 鍵、decimal pad 的小數點是否依 locale 變化**：本次未在 Apple 文件中查到明文。
6. **Face ID 相關 HIG 的張力**：Privacy 頁鼓勵用生物辨識保護常駐登入的 app，Managing accounts 頁建議避免 app 專屬生物辨識 opt-in 設定，Apple 沒說如何調和；§10.4 的折衷是推論。
7. **LINE/Telegram bot 綁定是否屬於 5.1.1(v) 所說的「social network」語境**：未查到明文，§10.1 是保守解讀。
8. **Cloudflare 等後端代管商是否算 App Privacy 的「third-party partners」**：頁面定義偏向 app 內的第三方程式碼，未直接涵蓋。
9. **Accessibility Nutrition Labels 何時強制**：官方只說未來會要求，沒有時程。
10. **my-money 後端是否支援交易軟刪除或還原**：超出本次研究範圍，影響 §7.4 的 undo 設計。
11. **SF Symbols 8 新符號清單、iOS 27 新增的 SwiftUI API 完整清單**：只確認了本文件引用的幾個 API 文件頁存在，沒有逐一核對 availability。
12. **「這筆買得起嗎」與現金流預測是否需要免責聲明**：沒查到 Apple 相關條款，§11 的建議屬一般風險控管。

## 來源清單（本次實際讀取）

**App Store 與 Developer 公告**
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)（Last Updated: June 8, 2026）
- [Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/)
- [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)
- [Apple Developer News](https://developer.apple.com/news/)、[News 2026-06-08（Guidelines 更新）](https://developer.apple.com/news/?id=a233fmpw)、[News 2026-09-09（提交開放與 2027 SDK 要求）](https://developer.apple.com/news/?id=k1mtkt1k)
- [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
- [TestFlight](https://developer.apple.com/testflight/)
- [Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)
- [Apple Newsroom 2026-09-14](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/)、[Apple security releases](https://support.apple.com/en-us/100100)

**HIG**（DocC JSON 全文）
- [What's new](https://developer.apple.com/design/whats-new/)、[Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)、[Designing for iPadOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ipados)、[Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)、[Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)、[Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)、[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)、[Searching](https://developer.apple.com/design/human-interface-guidelines/searching)、[Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)、[Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)、[Typography](https://developer.apple.com/design/human-interface-guidelines/typography)、[SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)、[Icons](https://developer.apple.com/design/human-interface-guidelines/icons)、[App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)、[Branding](https://developer.apple.com/design/human-interface-guidelines/branding)、[Layout](https://developer.apple.com/design/human-interface-guidelines/layout)、[Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views)、[Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)、[VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)
- [Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields)、[Virtual keyboards](https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards)、[Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data)、[Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers)、[Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)、[Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)、[Modality](https://developer.apple.com/design/human-interface-guidelines/modality)、[Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)、[Action sheets](https://developer.apple.com/design/human-interface-guidelines/action-sheets)、[Undo and redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo)、[Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)
- [Charts](https://developer.apple.com/design/human-interface-guidelines/charts)、[Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)
- [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)、[Launching](https://developer.apple.com/design/human-interface-guidelines/launching)、[Managing accounts](https://developer.apple.com/design/human-interface-guidelines/managing-accounts)、[Sign in with Apple](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)、[Settings](https://developer.apple.com/design/human-interface-guidelines/settings)、[Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
- [Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications)、[Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications)、[Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets)

**Developer Documentation**（DocC JSON 全文）
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/liquid-glass)、[Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)、[UIDesignRequiresCompatibility](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)
- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)、[iOS & iPadOS 27 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)、[Device Hub](https://developer.apple.com/documentation/xcode/device-hub)
- SwiftUI：[sidebarAdaptable](https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable)、[TabRole](https://developer.apple.com/documentation/swiftui/tabrole)、[TabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior)、[ToolbarItemVisibilityPriority](https://developer.apple.com/documentation/swiftui/toolbaritemvisibilitypriority)、[ToolbarOverflowMenu](https://developer.apple.com/documentation/swiftui/toolbaroverflowmenu)、[topBarPinnedTrailing](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/topbarpinnedtrailing)、[toolbarMinimizationBehavior(_:for:)](https://developer.apple.com/documentation/swiftui/view/toolbarminimizationbehavior(_:for:))、[ReservedRegion](https://developer.apple.com/documentation/swiftui/reservedregion)、[keyboardType(_:)](https://developer.apple.com/documentation/swiftui/view/keyboardtype(_:))、[TextField](https://developer.apple.com/documentation/swiftui/textfield)、[searchable](https://developer.apple.com/documentation/swiftui/view/searchable(text:placement:prompt:))、[confirmationDialog](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:))、[interactiveDismissDisabled(_:)](https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:))、[monospacedDigit()](https://developer.apple.com/documentation/swiftui/view/monospaceddigit())、[privacySensitive(_:)](https://developer.apple.com/documentation/swiftui/view/privacysensitive(_:))、[accessibilityChartDescriptor(_:)](https://developer.apple.com/documentation/swiftui/view/accessibilitychartdescriptor(_:))、[accessibilityReduceTransparency](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency)、[accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)、[colorSchemeContrast](https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast)
- [Swift Charts](https://developer.apple.com/documentation/charts)、[SectorMark](https://developer.apple.com/documentation/charts/sectormark)、[Audio graphs](https://developer.apple.com/documentation/accessibility/audio-graphs)、[TipKit](https://developer.apple.com/documentation/tipkit)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)、[Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)、[NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [NSFaceIDUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsfaceidusagedescription)、[Logging a User into Your App with Face ID or Touch ID](https://developer.apple.com/documentation/localauthentication/logging-a-user-into-your-app-with-face-id-or-touch-id)、[LABiometryType](https://developer.apple.com/documentation/localauthentication/labiometrytype)
- [Restricting keychain item accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)、[Password AutoFill](https://developer.apple.com/documentation/security/password-autofill)、[Preparing your UI to run in the background](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background)
- [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)、[Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Localization](https://developer.apple.com/documentation/xcode/localization)、[Supporting multiple languages in your app](https://developer.apple.com/documentation/xcode/supporting-multiple-languages-in-your-app)、[Preparing dates, currencies, and numbers for translation](https://developer.apple.com/documentation/xcode/preparing-dates-numbers-with-formatters)、[Data Formatting](https://developer.apple.com/documentation/foundation/data-formatting)

**WWDC26 sessions**（頁面與官方逐字稿）
- [Platforms State of the Union](https://developer.apple.com/videos/play/wwdc2026/102/)、[What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/)、[Refine accessibility for custom controls](https://developer.apple.com/videos/play/wwdc2026/220/)
