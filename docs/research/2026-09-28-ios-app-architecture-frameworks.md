# 原生 SwiftUI iOS app 的架構與工程框架選型(my-money.ios)

查核日期：2026-09-28

查核範圍:

- 架構模式：Apple 慣用資料流(社群俗稱 MV)、MVVM(`@Observable` ViewModel)、The Composable Architecture(TCA)、Clean Architecture / VIPER,以及 2026 年仍在更新的其他架構框架(Square Workflow、Spotify Mobius、Uber RIBs-iOS、ReSwift、ReactorKit、OneWay)。
- Dependency injection:SwiftUI `Environment` + initializer 注入、pointfreeco/swift-dependencies、hmlongco/Factory;另列出已停滯或已棄用的 Swinject、Resolver、Needle 作為排除依據。
- 專案/模組管理：純 `.xcodeproj`(buildable folders)、SwiftPM local packages、XcodeGen、Tuist。
- 持久化(SwiftData / Core Data / Keychain)、網路層(URLSession、Alamofire、Moya、Apple swift-openapi-generator)、測試(Swift Testing、XCTest、XCUIAutomation)。
- 後端現況：直接讀 web 版 repo [onion523/my-money @ `43a205d`](https://github.com/onion523/my-money/tree/43a205d4366337fbec9d672cfc49e27b4f2cf48c)(2026-09-27 的 HEAD),只看認證與 API 形狀，不評估後端本身。

來源規則：只用一手來源(developer.apple.com 文件與 WWDC session 頁、swift.org、swift-evolution、各框架官方 GitHub repo 與官方文件)。GitHub 活躍度一律取自 GitHub REST API,查詢時間 **2026-09-28 00:34(UTC+8)**,原始數據與 API URL 見[第 9 節](#9-github-活躍度原始數據)。

標記：**「推論」** = 我的工程判斷，不是來源原文;**「未查證」** = 這次沒有找到一手來源佐證。

不重複的範圍:DDD 的戰略/戰術設計(聚合、Bounded Context、repository 放哪一層等)由另一份研究 `2026-09-28-ddd-ios-swiftui.md` 負責。本文只評估各框架與「Domain / Application / Infrastructure / Presentation」四層的相容性與摩擦點。

---

## 結論

1. **架構模式選 Apple 慣用資料流，並採「每個畫面一個 `@Observable` 畫面 model」的做法(也就是 MVVM 的 ViewModel 角色),不用 TCA。** Apple 文件把「資料模型與 view 分離」當作提升模組化與可測性的做法([Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)),WWDC23 也把 `@State` / `@Environment` / `@Bindable` 的選法濃縮成三個問題([Discover Observation in SwiftUI, 9:39](https://developer.apple.com/videos/play/wwdc2023/10149/))。在 WWDC26 被問到 MVC / MVVM / VIPER / Clean 該選哪個時,SwiftUI 團隊的回答是「there's really no architecture that we expect you to adopt. SwiftUI is really designed to be architecture agnostic」([SwiftUI Group Lab, 1:03](https://developer.apple.com/videos/play/wwdc2026/8006/))。MV 與 MVVM 在 `@Observable` 之下只差命名與粒度(推論):畫面 model 就是 Presentation 層的 adapter,而 .NET 背景的人本來就熟悉 MVVM。
2. **DDD 分層用一個 SwiftPM local package 的多個 target 表達，讓編譯器強制相依方向;app target 只放 composition root。** 實際要切哪幾個 target(例如是否獨立出 Application 層、SwiftUI 畫面放 package 還是 app target),以 DDD 研究第 4.1 節的模組樹為準。本文的框架選型在兩種切法下都成立(推論)。Apple 官方建議用 local package 做模組化([Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages))。SwiftPM target 沒有設定時預設 `nonisolated`([SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)),Xcode 26 新建的 app 專案則預設 main actor([WWDC25 Embracing Swift concurrency, 4:40](https://developer.apple.com/videos/play/wwdc2025/268/))。這樣正好讓 Domain 保持與執行緒無關，讓 UI 留在 main actor(推論)。
3. **TCA 不適合這個專案。** 第一，官方 FAQ 自己說 TCA 在「主要從網路載入 JSON 再顯示的 reader app」上不太能發揮，也說可以先用 vanilla SwiftUI、之後需要再轉([TCA FAQ](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Sources/ComposableArchitecture/Documentation.docc/Articles/FAQ.md))。這個 app 的業務規則大多在後端，正好是這種型態(推論)。第二,TCA 2.0 是根本性重新設計，目前只以付費會員 beta 形式提供([Point-Free, 2026-04-01](https://www.pointfree.co/blog/posts/206-beta-preview-composablearchitecture-2-0)),1.25 起的版本則陸續 deprecate API 為 2.0 鋪路([1.25.0 release](https://github.com/pointfreeco/swift-composable-architecture/releases/tag/1.25.0))。第三，它的 library target 會帶進 12 個 package 再加上 swift-syntax([Package.swift @1.26.2](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Package.swift))。
4. **VIPER 不採用;Clean Architecture 只取「分層 + 依賴反轉」,不取 Interactor / Presenter / Router 的樣板。** SwiftUI 的導覽由資料驅動(`navigationDestination(for:)` 搭配值，見 [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack)),和 VIPER 的命令式 Router 有概念衝突(推論)。
5. **DI 用 initializer 注入，在 `App` 裡設一個 composition root,app 層級的共享物件再用 SwiftUI `Environment` 往下傳，不引入第三方 DI。** `@Environment` 只能在 view 中讀取([Environment](https://developer.apple.com/documentation/swiftui/environment)),所以非 view 的型別(畫面 model、use case)一律走 initializer 注入，對應 .NET 的 constructor injection(推論)。日後如果真的需要 container,優先考慮 Factory(0 個 runtime 相依，本月仍有 release,見第 3 節)。
6. **專案管理用純 `.xcodeproj` + buildable folders + 一個 local package,不用 XcodeGen 或 Tuist。** Buildable folders 只在專案檔記錄資料夾路徑、不列舉檔案，官方說明可減少 diff 並避免版本控制衝突([Xcode 16 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes))。Tuist 自己也寫到，buildable folders 讓 agent 與 CI 在 Xcode UI 外新增檔案時不必重新產生專案([Tuist changelog 2025-08-11](https://github.com/tuist/tuist/blob/main/server/priv/marketing/changelog/2025.08.11-buildable-folders.md))。單一 app target 的規模下，產生器的收益抵不過多一道工具鏈(推論)。
7. **v1 完全不用 SwiftData / Core Data。** JWT 存 Keychain,直接用 Security framework 的 generic password;非敏感的偏好設定(例如上次選的「視角」)存 `UserDefaults`。後端的 JWT 效期固定 30 天，沒有 refresh 路由([jwt.ts](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/middleware/jwt.ts)、[auth.ts](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/handlers/auth.ts)),所以 token 儲存的需求很單純。
8. **網路層用 URLSession async/await + Codable,自己寫一個薄的 APIClient,不用 Alamofire。** 依套件政策，第一方做得到就不引第三方;`data(for:delegate:)` 從 iOS 15 起就有([URLSession](https://developer.apple.com/documentation/foundation/urlsession/data(for:delegate:)))。Apple 的 swift-openapi-generator 需要 OpenAPI 文件([README](https://github.com/apple/swift-openapi-generator)),但後端只相依 `hono`、repo 裡沒有任何 OpenAPI 檔([backend/package.json](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/package.json)),v1 不採用。
9. **Unit / integration test 用 Swift Testing,UI 流程用 XCTest + XCUIAutomation,兩者分開 target。** Apple 建議新的 unit test 用 Swift Testing,UI test 與 performance test 繼續用 XCTest,而且不要在同一個 test 裡混用兩者的 API([XCTest](https://developer.apple.com/documentation/xctest))。Swift Testing 與 XCTest 的互通(ST-0021)要到 **Swift 6.4** 才有([proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0021-targeted-interoperability-swift-testing-and-xctest.md)),Xcode 26.6 用的是 Swift 6.3([Xcode 26.6 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes)),所以拿不到。
10. **Concurrency 設計:Domain 型別做成 `Sendable` 的 value type,Infrastructure 維持 `nonisolated`,畫面 model 放在 main actor。** 這符合 Apple「library 提供 nonisolated API,由呼叫端決定要不要移出 main actor」的建議([WWDC25 268, 13:10](https://developer.apple.com/videos/play/wwdc2025/268/)),也和「把 async 邏輯與 view 邏輯分開，以便不 import SwiftUI 就能測試」的建議一致([WWDC25 Explore concurrency in SwiftUI, 16:53 / 23:47](https://developer.apple.com/videos/play/wwdc2025/266/))。
11. **Xcode 26.6 下 `@State` 還不是 lazy,畫面 model 的建立位置要設計好。** 文件寫明 `State` 每次 SwiftUI 建立 view 時都會實例化預設值([State](https://developer.apple.com/documentation/swiftui/state))。`@State` 要到「2027 releases」才改成 macro 並變成 lazy([WWDC26 What's new in SwiftUI, 19:58](https://developer.apple.com/videos/play/wwdc2026/269/))。在那之前，畫面 model 應由父層或路由建立後傳入，或照文件用 `.task` 延後建立。
12. **升級風險:Xcode 27(Swift 6.4)已發布**([Xcode 27 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)),而 `@State` 改為 macro 在某些寫法下會 source-breaking([WWDC26 269, 23:48](https://developer.apple.com/videos/play/wwdc2026/269/))。主流套件的 `main` 分支已經用 `swift-tools-version: 6.4`,不過都附有 6.3 以下可用的 fallback manifest(見 [6.3 節](#63-第三方套件在-xcode-266swift-63-下能否解析)),目前不影響 Xcode 26.6 的前提。

---

## 比較表

活躍度取自 GitHub API(2026-09-28)。「學習成本」與「DDD 相容性」兩欄全部是**推論**,評估對象是熟悉 .NET DDD / Clean Architecture 的開發者。「相依數」指加進 app 的 runtime package 數，不含建置工具。

| 類別 | 候選 | 第一方 | 活躍度 | Swift 6 / iOS 26 支援 | 學習成本 | 與 DDD 分層相容性 | 測試性 | 相依數 |
|---|---|---|---|---|---|---|---|---|
| 架構 | Apple 資料流(MV:`@Observable` + `@State` / `@Environment`) | 是(Observation 是標準函式庫模組，見 [SE-0395](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md)) | 隨 SDK 演進,WWDC26 仍有新功能 | 原生;Observation 需 iOS 17+ | 低 | 中高:model 不必 import SwiftUI;但 Apple 範例常把邏輯直接寫在 model,容易混層 | 高([WWDC25 266](https://developer.apple.com/videos/play/wwdc2025/266/) 鼓勵不 import SwiftUI 就能測) | 0 |
| 架構 | MVVM(`@Observable` 畫面 model) | 模式，只用第一方 API | 同上 | 同上;Xcode 26.6 下 `@State` 非 lazy | 低(.NET 熟 MVVM) | 高:VM = Presentation adapter,只呼叫 Application 層 | 高 | 0 |
| 架構 | TCA 1.26.2 | 否 | 高(14,937★,2026-09-18 push);2.0 為付費 beta | Swift 6 mode 編譯、iOS 16+;Xcode 26.6 用 `Package@swift-6.1.swift` | 高 | 中低:Reducer + State/Action 主導結構，容易吞掉 Application 層 | 很高(TestStore) | 12 + swift-syntax |
| 架構 | Clean Architecture(僅分層 + 依賴反轉) | 模式 | — | 與 Swift 版本無關 | 低 | 很高(同構) | 高 | 0 |
| 架構 | VIPER | 模式 | — | 同上;Router 與 SwiftUI 資料驅動導覽衝突 | 中 | 高，但樣板多 | 高 | 0 |
| 架構 | Workflow / Mobius / RIBs-iOS / ReSwift / ReactorKit / OneWay | 否 | 低至中(見第 9 節) | 未查證 | 高 | 未評估 | — | ≥1 |
| DI | initializer 注入 + `Environment` | 是 | — | 原生;`@Entry` 宣告自訂 key | 低 | 很高(= Pure DI / composition root) | 高(手寫替身) | 0 |
| DI | swift-dependencies 1.17.1 | 否 | 中高(2,195★,2026-08-28 release) | Xcode 26.6 用 `Package@swift-6.3.swift`;iOS 15+ | 中 | 中:`@Dependency` 是 task-local 的環境式存取，不是顯式建構式注入 | 很高(`.dependencies` test trait) | 4(用 macro 再 + swift-syntax) |
| DI | Factory 3.4.1 | 否 | 高(2,904★,2026-09-25 release) | Swift 6 language mode;iOS 15+ | 低中(像 .NET container) | 中:`Container.shared` + `@Injected` 偏 service locator | 高(`.container` trait) | 0 |
| DI | Swinject / Resolver / Needle | 否 | 低:停滯或已棄用 | 未查證 | — | — | — | — |
| 專案 | `.xcodeproj` + buildable folders | 是 | 隨 Xcode | Xcode 16+ | 低 | 中(只有資料夾，沒有編譯期邊界) | — | 0 |
| 專案 | SwiftPM local package(多 target) | 是 | 隨工具鏈 | tools-version ≥ 6.0 即為 Swift 6 mode | 低中 | 很高(相依方向由編譯器強制) | 很高(`swift test` 可在 macOS host 跑) | 0 |
| 專案 | XcodeGen 2.46.0 | 否 | 中高(8,804★,2026-07-16 release) | 2.44.0 起支援 synced folder | 低 | 中 | — | 0(建置工具) |
| 專案 | Tuist 4.209.0 | 否 | 很高(5,815★,2026-09-27 push) | 支援 buildable folders | 中 | 高(Project.swift 型別化的模組圖) | — | 0(建置工具) |
| 網路 | URLSession + Codable | 是 | — | async API 從 iOS 15 起 | 低 | 很高(Infrastructure adapter) | 高(`URLProtocol` stub) | 0 |
| 網路 | Alamofire 5.12.2 | 否 | 高(42,417★,2026-09-10 release) | 最低 Swift 6.0 / Xcode 16 | 低中 | 高 | 中 | 1 |
| 網路 | swift-openapi-generator 1.13.1 | Apple 開源(非 SDK) | 中高(1,975★,2026-09-01 release) | tools-version 6.1 | 中 | 高(生成的 DTO 放 Infrastructure) | 高 | 3(runtime、urlsession、http-types)以上;**前提是要有 OpenAPI 文件** |
| 網路 | Moya | 否 | 低(最後 release 2022-08) | 未查證 | — | — | — | ≥2 |
| 持久化 | Keychain(Security framework) | 是 | — | 原生 | 中(CF 字典式 API) | 高(包成 `TokenStore` adapter) | 中(需要替身) | 0 |
| 持久化 | SwiftData | 是 | — | iOS 17+ | 中 | 中低(`@Model` 同時是持久化模型與領域模型) | — | 0;**v1 不需要** |
| 持久化 | Valet 5.1.1 | 否 | 中(4,171★,2026-09-09 release) | 未查證 | 低 | 高 | — | 1;依政策不需要 |
| 測試 | Swift Testing | 是(工具鏈內建) | 高(`swift-6.4.0-RELEASE`,2026-09-15) | Swift 6.3 有 cancellation、issue severity、image attachments | 低 | — | 很高 | 0 |
| 測試 | XCTest + XCUIAutomation | 是 | — | UI test 只能用它 | 低 | — | UI 流程、錄製、多語系 test plan | 0 |

---

## 1. 前提的事實核對(與選型直接相關的部分)

### 1.1 工具鏈

- Xcode 26.6 內含 Swift 6.3 與 iOS / iPadOS 26.5 SDK([Xcode 26.6 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes))。
- Xcode 27 已發布，內含 Swift 6.4 與 iOS 27 SDK([Xcode 27 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes))。本文**不挑戰** Xcode 26.6 的前提，只標出哪些功能要 Xcode 27 才有:`@State` macro 與 lazy 初始化、Swift Testing / XCTest 互通。
- GitHub Actions 的 `macos-26-arm64` image(20260907 版)預設 Xcode 26.6,內含 iOS 26.5 simulator runtime;runner 也已提供 Xcode 27 public preview([runner-images macos-26-arm64 README](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md))。

### 1.2 後端 API 的形狀(影響網路層與 token 儲存)

以下讀自 [onion523/my-money @ 43a205d](https://github.com/onion523/my-money/tree/43a205d4366337fbec9d672cfc49e27b4f2cf48c):

- 認證是 HS256 JWT,`exp = now + 30 天`。middleware 接受 `Authorization: Bearer <token>`,也接受 query string `?token=`([jwt.ts](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/middleware/jwt.ts))。
- `auth` 路由只有 `POST /register` 與 `POST /login`,沒有 refresh 端點([auth.ts](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/handlers/auth.ts))。
- 回應統一包成 `{ success, data, error }`。web client 遇到 401 會清掉 token 並導回登入頁([web/src/api/client.ts](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/api/client.ts))。
- 路由群組:`/auth`、`/accounts`、`/transactions`、`/recurring`、`/goals`、`/budgets`、`/forecast`、`/export`、`/households`、`/bot`([index.ts](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/index.ts))。
- 後端 runtime 相依只有 `hono`,repo 的檔案樹裡沒有 OpenAPI / Swagger 檔([backend/package.json](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/package.json))。

推論:iOS 端需要的只是「Bearer header + envelope 解碼 + 401 時登出」,不需要攔截器鏈、自動 refresh、multipart 這類重量級網路功能。

---

## 2. 架構模式

### 2.1 Apple 慣用資料流(社群俗稱 MV)

「MV」不是 Apple 的用語，而是社群對下列做法的俗稱(推論)。Apple 文件使用的詞是 data model / model data。

**Apple 的官方說法:**

- 建立 data model,讓資料與 view 分離，「promotes modularity, improves testability」([Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app))。
- 用 `@Observable` macro 讓 model 可被觀察;view 只在 `body` 實際讀到的屬性改變時才更新。source of truth 用 `@State` 持有;要在整個 view 階層共享時，可以逐層傳遞，也可以用 `.environment(_:)` 放進 environment(同上)。
- 以型別為 key 讀 `@Environment(Library.self)` 時，如果 environment 裡沒有該物件,SwiftUI 會 throw exception;宣告成 optional 則回傳 `nil`([Environment](https://developer.apple.com/documentation/swiftui/environment))。自訂 environment 值用 `@Entry` macro 宣告([Entry()](https://developer.apple.com/documentation/swiftui/entry()))。
- WWDC23 的判斷準則原文:「Does this model need to be state of the view itself? If so, use '@State'. Does this model need to be part of the global environment of the application? If so, use '@Environment'. Does this model just need bindings? If so, use the new '@Bindable'.」([Discover Observation in SwiftUI, 9:39](https://developer.apple.com/videos/play/wwdc2023/10149/))
- WWDC25:「It's best to separate the logic for async work from your view logic.」「See if you can do it without importing SwiftUI.」([Explore concurrency in SwiftUI, 16:53 / 23:47](https://developer.apple.com/videos/play/wwdc2025/266/))
- Observation 是標準函式庫模組，不屬於 SwiftUI([SE-0395](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md))。iOS 26 起另有 `Observations` async sequence,可以在 SwiftUI 以外觀察 `@Observable` 的交易式變更([Observations](https://developer.apple.com/documentation/observation/observations)、[SE-0475](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md))。

**Xcode 26.6 下要注意的地方:**

- `State` 每次 SwiftUI 實例化 view 時都會實例化預設值;文件建議用 `.task` 延後建立物件([State](https://developer.apple.com/documentation/swiftui/state))。
- 「In the 2027 releases … classes initialized and stored using State properties are now lazy … thanks to the conversion of State from a Dynamic Property to a macro」,而且這個行為回溯到 iOS 17([WWDC26 What's new in SwiftUI, 19:58](https://developer.apple.com/videos/play/wwdc2026/269/))。推論:macro 屬於編譯期功能，所以用 Xcode 26.6 建置時拿不到 lazy 行為，要等升級到 Xcode 27。這點未查證 Apple 是否另有明文說明。

**與 DDD 分層的相容性:**

- 優點:`@Observable` 不需要 SwiftUI,Application 層如果需要可觀察的狀態(例如登入 session),可以放在不 import SwiftUI 的 target。畫面 model 只呼叫 Application 層(推論)。
- 摩擦 1:Apple 的範例習慣把業務邏輯直接寫在 `@Observable` class,容易把 Domain 規則寫進 Presentation(推論)。
- 摩擦 2:`@Observable` 只能用在 class,和 DDD 偏好的 value object(struct)是兩回事。解法是 Domain 用 struct,畫面 model 用 class 持有 Domain 值(推論)。
- 摩擦 3:`@Environment` 只在 view 內可讀，不能當作通用的 service locator(推論，依據 [Environment](https://developer.apple.com/documentation/swiftui/environment)「reads a value from a view's environment」)。

### 2.2 MVVM(`@Observable` ViewModel)

- 做法：每個畫面一個 `@MainActor @Observable final class XxxModel`(或叫 ViewModel),持有畫面狀態(載入中、錯誤、表單值)並呼叫 Application 層的 use case。
- Apple 一手資料的立場:
  - 文件與主要 session([Managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)、[WWDC23 10149](https://developer.apple.com/videos/play/wwdc2023/10149/))都沒有使用「ViewModel」這個詞;WWDC25 266 支持「把 async 邏輯從 view 抽出來」([WWDC25 266](https://developer.apple.com/videos/play/wwdc2025/266/))。
  - WWDC26 SwiftUI Group Lab 被問到 MVC / MVVM / VIPER / Clean 時的回答:「there's really no architecture that we expect you to adopt. SwiftUI is really designed to be architecture agnostic … any architecture that works for your specific app … should work with SwiftUI」。同一段也建議「keep your SwiftUI views so that just a projection of your data model to pixels and then design the data to be as robust and testable as you can」([WWDC26 8006, 1:03](https://developer.apple.com/videos/play/wwdc2026/8006/))。
  - 所以「Apple 反對 MVVM」的說法沒有一手來源支持;Apple 的明文立場是架構中立。
- 推論:`@Observable` 之下，「每畫面一個 model」的 MVVM 和 MV 在技術上沒有差別，差別只在粒度與命名。
- 與 DDD 分層的相容性：高。VM 就是 Presentation 的 adapter:它把 Domain 值轉成顯示字串、處理使用者意圖，再委派給 Application 層。這和 .NET 的 WPF / MAUI MVVM 心智模型一致(推論)。
- 摩擦 1:同一份資料被多個畫面顯示時(例如帳戶餘額同時出現在儀表板與帳戶頁),各畫面的 VM 各自持有副本就可能不同步。推論的解法是另設少數 app 層級、以 `Environment` 共享的 `@Observable` model(Session、目前家庭)。
- 摩擦 2:Xcode 26.6 下 `@State private var vm = XxxModel(...)` 不是 lazy(見 2.1),而且 view 初始化時就必須備齊相依。解法是由父層或 `navigationDestination` 建立 VM 後傳入(推論)。

### 2.3 The Composable Architecture(TCA)

**版本與支援狀態(查詢日 2026-09-28):**

- 最新 release 是 **1.26.2(2026-08-28)**。另有 1.23.3(2026-09-18),是舊版本線的 patch([releases API](https://api.github.com/repos/pointfreeco/swift-composable-architecture/releases))。
- 1.26.2 的 `Package.swift` 為 `swift-tools-version: 6.4`,另附 `Package@swift-6.1.swift` 給 Swift 6.1 到 6.3 的工具鏈使用，所以 Xcode 26.6 可以解析。平台 `.iOS(.v16)`,並宣告 `swiftLanguageModes: [.v6]`([Package.swift @1.26.2](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Package.swift))。
- 1.24.0 把 iOS 16 以下與 Swift 6.1 以下列為 deprecated,並修了 Xcode 26.4 的 shared bindings 問題([1.24.0](https://github.com/pointfreeco/swift-composable-architecture/releases/tag/1.24.0))。1.26.0 修了 Xcode 26 的 `xcodebuild archive` 失敗，並支援 Xcode 27 beta 1([1.26.0](https://github.com/pointfreeco/swift-composable-architecture/releases/tag/1.26.0))。
- 授權:MIT([LICENSE](https://github.com/pointfreeco/swift-composable-architecture/blob/main/LICENSE))。

**2.0 的進度:**

- 2026-04-01 發布「Beta Preview: ComposableArchitecture 2.0」,描述為 fundamental redesign(新的 `@Feature` macro、Store 預設 `@MainActor`、另有 `StoreActor`),以 Point-Free Max 付費會員 beta 的形式提供。套件會附 `ComposableArchitecture1` 相容層，可以逐個 feature 遷移([Point-Free blog](https://www.pointfree.co/blog/posts/206-beta-preview-composablearchitecture-2-0))。
- 1.25 帶來大量為 2.0 鋪路的 deprecation,並提供 `ComposableArchitecture2Deprecations` SwiftPM trait([1.25.0](https://github.com/pointfreeco/swift-composable-architecture/releases/tag/1.25.0)、[Package.swift](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Package.swift))。
- 2.0 的正式發布日、最低 iOS / Swift 版本、授權：未查證(公開文章沒有寫)。

**相依數:**

`ComposableArchitecture` target 直接相依 12 個 package:swift-case-paths、swift-clocks、combine-schedulers、swift-concurrency-extras、swift-custom-dump、swift-dependencies、swift-identified-collections、swift-issue-reporting、swift-collections、swift-perception、swift-sharing、swift-navigation。另外 macro target 相依 swift-syntax([Package.swift @1.26.2](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Package.swift))。

**官方對「何時該用」的說法(FAQ 原文摘要):**

- 不建議在剛學 Swift / SwiftUI 時使用。
- 「We also don't think TCA really shines when building simple "reader" apps that mostly load JSON from the network and display it.」
- 「it can be fine to start a project with vanilla SwiftUI … and then transition to TCA later」

以上出自 [FAQ.md @1.26.2](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Sources/ComposableArchitecture/Documentation.docc/Articles/FAQ.md)。FAQ 也說明大量學習內容免費(文件與 SyncUps 教學),但部分影片只限訂閱者(同上)。

**學習成本:** 高(推論)。要同時理解 State / Action / Reducer / Effect / Store scoping / `@Dependency` / `@Shared` / TestStore 的 exhaustive 斷言;2.0 又會改寫主要 API。

**與 DDD 分層的相容性(推論):**

- 相容的部分:TCA 強調用 value type 建模 domain、把副作用和純邏輯分開(FAQ「Do I need to be familiar with functional programming」一節)。這和 DDD 的 value object、以及 Domain 保持純淨的要求一致。
- 摩擦 1:Reducer 同時承擔 Application service 與 Presentation 的狀態轉移，四層容易被壓成兩層(Reducer + Dependency client)。
- 摩擦 2:swift-dependencies 支援 protocol 型與 struct-of-closures 型兩種相依設計([Designing dependencies](https://github.com/pointfreeco/swift-dependencies/blob/main/Sources/Dependencies/Documentation.docc/Articles/DesigningDependencies.md)),但 TCA 範例以後者為主([README](https://github.com/pointfreeco/swift-composable-architecture)),和 .NET 慣用的 interface-based repository 風格不同。
- 摩擦 3:框架主導專案結構，之後要換掉的成本高;2.0 又是一次大改。

### 2.4 Clean Architecture / VIPER

- 兩者都沒有 Apple 一手文件背書，也沒有「官方框架」可查。GitHub 上較知名的 [nalexn/clean-architecture-swiftui](https://github.com/nalexn/clean-architecture-swiftui) 是範例 app,不是框架(6,605★,最後 push 2025-07-14,最後 release 3.0 在 2024-12-08)。
- Clean Architecture(分層 + 依賴反轉):和 DDD 四層同構，熟悉度最高。成本只在介面與 DTO 對映的樣板程式碼(推論)。
- VIPER(View / Interactor / Presenter / Entity / Router):
  - SwiftUI 導覽是「把值 push 進 stack,由 `navigationDestination(for:)` 決定目的畫面」的資料驅動模型([NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack))。VIPER 的 Router 若要命令式地建構並推送 view,就得和這套模型對抗(推論)。
  - Presenter 的角色在 `@Observable` 下和 VM 重疊，對 11 個畫面的 app 來說是多出來的一層(推論)。
- 建議(推論):採用 Clean Architecture 的「層與相依方向」,Presentation 內部用第 2.2 節的畫面 model,不引入 VIPER 的五件套。

### 2.5 2026 年其他仍在更新的架構框架

| 框架 | 活躍度(API) | 定位 | 評估 |
|---|---|---|---|
| [square/workflow-swift](https://github.com/square/workflow-swift) | 373★,v6.0.1(2026-08-25) | Square 的 unidirectional 狀態機框架 | 社群小，學習成本高，不列入(推論) |
| [spotify/Mobius.swift](https://github.com/spotify/Mobius.swift) | 583★,0.8.0(2026-08-05) | MVI / loop 架構 | 仍在 0.x,不列入(推論) |
| [uber/RIBs-iOS](https://github.com/uber/RIBs-iOS) | 193★,1.1.0(2026-07-12) | Uber 跨平台架構,iOS 版已拆出獨立 repo([uber/RIBs README](https://github.com/uber/RIBs)) | 以大型團隊與 UIKit 為主要場景(推論),不列入 |
| [ReSwift/ReSwift](https://github.com/ReSwift/ReSwift) | 7,588★,最後 push 2024-04-22,最後 release 6.1.1(2023-01) | Redux | 停滯，排除 |
| [ReactorKit/ReactorKit](https://github.com/ReactorKit/ReactorKit) | 2,784★,最後 release 3.2.0(2022-01) | RxSwift 系 | 停滯且相依 RxSwift,排除 |
| [DevYeom/OneWay](https://github.com/DevYeom/OneWay) | 109★,3.1.0(2026-06-03) | 輕量 unidirectional | 社群太小，排除 |

結論:2026 年真正主流又活躍的第三方 SwiftUI 架構框架只有 TCA(推論，依據上表與第 9 節的 star 數與 release 頻率)。

---

## 3. Dependency injection

### 3.1 SwiftUI `Environment` + initializer 注入(建議)

- `@Environment` 用來讀 view environment 的值，可放 `@Observable` 物件(`.environment(obj)` 搭配 `@Environment(Type.self)`),也可用 `@Entry` 定義 key path 型的自訂值([Environment](https://developer.apple.com/documentation/swiftui/environment)、[Entry()](https://developer.apple.com/documentation/swiftui/entry()))。
- 限制:environment 只在 view 階層內可讀(同上)。所以 use case、repository、APIClient 都要走 initializer 注入(推論)。
- 做法(推論):
  - 在 `@main struct MyMoneyApp: App` 裡建立 composition root:`APIClient` → repository 實作 → use case → app 層級 model。
  - app 層級 model(例如 `SessionModel`)用 `.environment(_:)` 注入。
  - 畫面 model 由路由或父層用 initializer 建立。
  - 這就是 .NET 所說的 Pure DI:相依關係在型別簽章上看得到，對 AI agent 也最好追蹤。
- 測試：手寫 protocol 的 fake 或 stub。Swift Testing 的 test 可以直接 `init` 被測物並傳入替身(推論)。

### 3.2 pointfreeco/swift-dependencies

- 1.17.1(2026-08-28),2,195★,MIT([repo](https://github.com/pointfreeco/swift-dependencies))。自述「A dependency management library inspired by SwiftUI's "environment."」,提供 `.dependencies` 的 Swift Testing trait 與 `#Preview(traits: .dependencies { … })`([README](https://github.com/pointfreeco/swift-dependencies))。
- Manifest:`main` 為 tools-version 6.4,另附 `Package@swift-6.3.swift`,Xcode 26.6 可以解析;平台 iOS 15+([Package.swift](https://github.com/pointfreeco/swift-dependencies/blob/1.17.1/Package.swift))。
- 相依:`Dependencies` target 相依 swift-clocks、combine-schedulers(這兩個可以用 trait 關掉)、swift-concurrency-extras、IssueReporting;`DependenciesMacros` 另外相依 swift-syntax(同上)。
- 與 DDD 的相容性：中(推論)。`@Dependency(\.x)` 是環境式存取，不是顯式建構式注入。好處是測試覆寫範圍精確，缺點是型別簽章上看不出相依。官方同時支援 protocol 型相依([Designing dependencies](https://github.com/pointfreeco/swift-dependencies/blob/main/Sources/Dependencies/Documentation.docc/Articles/DesigningDependencies.md)),所以 repository interface 可以維持 protocol。
- 推論：只有採用 TCA 時它才是自然選擇;不用 TCA 的話，引入 4 個以上的 package 換取測試覆寫的便利，對這個規模不划算。

### 3.3 hmlongco/Factory

- 3.4.1(2026-09-25),2,904★,MIT,runtime 相依 0(`Package.swift` 只相依 swift-docc-plugin),`swiftLanguageModes: [.version("6")]`([Package.swift](https://github.com/hmlongco/Factory/blob/main/Package.swift))。
- 3.4.0 把最低版本提高到 iOS 15,以支援 Xcode 27([3.4.0 release](https://github.com/hmlongco/Factory/releases/tag/3.4.0))。
- README 提到：支援 Observation 與 `@MainActor`,提供 `@InjectedObservable`;`FactoryTesting` 提供 Swift Testing 的 `.container` trait,讓測試可以平行執行。已知問題：在全域 MainActor 預設下,nonisolated 的 service class 可能因 Swift 6.2 的問題無法用 `@Injected` 系列 property wrapper,需改用 `dependency(\.x)` 函式([README](https://github.com/hmlongco/Factory))。
- 與 DDD 的相容性：中(推論)。container 概念接近 .NET 的 `IServiceCollection`,但 `Container.shared` 搭配 `@Injected` 屬於 service locator 風格。本專案 app target 預設 MainActor、package target 預設 nonisolated,正好會碰到上面那個 README 列出的 Swift 6.2 限制。
- 定位(推論):如果日後 composition root 大到難以手動維護，它是備案。0 個相依、維護活躍，是它勝過 swift-dependencies 的地方。

### 3.4 排除的 DI 套件

- Swinject:最後 push 與最後正式 release 都在 2025-09-01(2.10.0),3.0.0 停在 rc-2,已超過一年沒有動靜([API](https://api.github.com/repos/Swinject/Swinject))。
- Resolver:README 寫明「Resolver is now officially deprecated and replaced by … Factory」([README](https://github.com/hmlongco/Resolver))。
- uber/needle:最後 release v0.25.1(2024-09-06)([API](https://api.github.com/repos/uber/needle/releases))。

---

## 4. 專案與模組管理

### 4.1 純 `.xcodeproj` + buildable folders(建議)

- Xcode 16 release notes 原文:「Buildable folders only record the folder path into the project file without enumerating the contained files. This minimizes diffs to the project when files are added and removed, and avoids source control conflicts with your team.」群組可以用「Convert to Folder」轉換([Xcode 16 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes))。
- Apple 文件同樣說明，選「Create folders」可以「minimize changes to your project file when you add or remove files」([Managing files and folders in your Xcode project](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project))。
- Xcode 16 起新專案範本是否預設為 buildable folders:未查證(release notes 只寫了 New Group 預設建立帶資料夾的 group)。
- 對 merge conflict 的影響(推論):用了 buildable folders 之後,`.pbxproj` 只在新增 target、package、build setting 時才會變動;單人加 AI agent 的開發模式下，衝突機率很低。
- 對 AI agent 的影響:
  - Xcode 26.3 引入 agentic coding 與外部 agent 的權限控管([Xcode 26.3 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_3-release-notes))。外部 agent(文件舉例 Claude Code、Codex)可透過 `xcrun mcpbridge` 用 MCP 建置與執行測試，但要先在 Xcode 開啟專案([Giving external agents access to Xcode](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode))。
  - buildable folders 讓 agent 直接在磁碟新增 `.swift` 檔就能被編譯，不必編輯 `.pbxproj`(推論;Tuist 的 changelog 也有同樣描述，見 4.4)。

### 4.2 SwiftPM local packages 切模組(建議搭配 4.1)

- Apple 的做法：用 File > New > Package 建立 local package,放在同一個 repo,再把 library product 加到 app target 的「Frameworks, Libraries, and Embedded Content」([Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages))。
- Manifest 用 `swift-tools-version: 6.0` 以上，所有 target 就會啟用 Swift 6 language mode([swift-migration-guide: EnableDataRaceSafety](https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/EnableDataRaceSafety.md))。沒有設定 `.defaultIsolation` 時，模組預設 `nonisolated`([SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md))。
- `swift test` 可以直接跑 package 的測試([swift test](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/swifttest/))。推論:package 若同時宣告 `.macOS(.v26)`,Domain / Application 的測試就能在 macOS host 上執行，不必開 simulator,CI 會更快。
- 與 DDD 的相容性：很高(推論)。Domain / Application / Infrastructure 各是一個 target,依賴方向寫在 manifest 裡，違規 import 會直接編譯失敗，效果等同 .NET 分專案加 ProjectReference。

### 4.3 XcodeGen

- 2.46.0(2026-07-16),8,804★,MIT。用 YAML 或 JSON spec 產生專案，主打「remove your .xcodeproj from git, which means no more merge conflicts」([README](https://github.com/yonaskolb/XcodeGen))。
- 2.44.0 起基本支援 Xcode 16 synchronized folders(`TargetSource.type: syncedFolder`),2.45.x 陸續修正 synced folder 相關 bug([CHANGELOG](https://github.com/yonaskolb/XcodeGen/blob/master/CHANGELOG.md))。
- 推論：它最大的賣點是避免衝突，而這已經被 buildable folders 解掉大半;代價是 CI 與本機都多一道 `xcodegen generate`,`.xcodeproj` 不進 git 之後,Xcode MCP 與新 clone 的人也要先產生專案。

### 4.4 Tuist

- CLI 最新穩定版 4.209.0(2026-09-21),repo 5,815★(2026-09-27 仍有 push)([releases API](https://api.github.com/repos/tuist/tuist/releases))。
- 授權：預設 MIT,`server/` 等目錄另有授權([LICENSE.md](https://github.com/tuist/tuist/blob/main/LICENSE.md));GitHub API 因此回報 `NOASSERTION`。
- 用 `Project.swift` 等 Swift DSL 描述專案，再用 `tuist generate` 產生 Xcode 專案([Tuist docs: Generated projects](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/features/projects.md))。官方文件站 tuist.dev 對自動化抓取回傳 Cloudflare challenge,所以這裡引用的是 repo 內同一份文件的原始檔。
- 2025-08-11 起支援 buildable folders。官方原文提到的好處是:「eliminate the need to regenerate projects when files are added outside of Xcode's UI—particularly valuable for automated agents and CI/CD pipelines」([changelog](https://github.com/tuist/tuist/blob/main/server/priv/marketing/changelog/2025.08.11-buildable-folders.md))。
- 安裝建議用 mise 釘版本([Install Tuist](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/install-tuist.md))。
- 推論:Tuist 的強項在多模組大型專案的型別化模組圖、快取與選擇性測試。本專案只有一個 app target 加一個 local package,用不到這些，卻要多承擔工具鏈與版本釘選。

### 4.5 專案骨架與 DDD 研究的對齊(推論)

模組樹(要切哪些 target、repository protocol 放哪層)由 DDD 研究的第 4.1 / 4.2 節決定。那份研究提的是 `MyMoneyDomain` / `MyMoneyAPI`(ACL)/ `MyMoneyFeatures`(SwiftUI View + `@Observable` store,`defaultIsolation(MainActor)`)/ `MyMoneyTestSupport` 四個 target,App 只做組裝。從工程框架的角度看，本文的建議和它相容:

```
my-money.ios/
├─ MyMoney.xcodeproj        ← buildable folders;只有 App 與 UITests 兩個 target(本文 4.1)
├─ App/                      ← composition root(本文 3.1 的 initializer 注入 + Environment)
├─ MyMoneyUITests/           ← XCTest + XCUIAutomation(本文 7.2)
└─ Packages/MyMoneyKit/      ← 單一 local package、多 target(本文 4.2);target 切法見 DDD 研究 4.1
   └─ Package.swift          ← swift-tools-version 6.x;Xcode 26.6 下最高 6.3
```

- 如果 SwiftUI 畫面放在 package 的 Features target:
  - 要注意 `swift test` 在 macOS host 上會連同 SwiftUI 程式碼一起為 macOS 編譯。只用 iOS 的 API(例如部分 toolbar placement)會需要條件編譯，或改為只在 iOS simulator 上用 `xcodebuild test` 跑(推論，未實測)。
  - Domain / API 的測試不受影響，仍可在 macOS host 上跑。
- DDD 研究也在本機實測指出:SwiftPM 的增量建置會放過「沒宣告相依卻 import」的違規，要在 CI 加 `swift build --explicit-target-dependency-import-check error`(見該研究 3.7 節;本文沒有重新驗證)。

---

## 5. 持久化

- **v1 不需要 SwiftData / Core Data**(推論)。SwiftData 的定位是「managed persistence and efficient model fetching」([SwiftData](https://developer.apple.com/documentation/swiftdata)),但 v1 沒有離線需求，資料的 source of truth 在後端。多一層本機模型只會帶來同步與失效問題。
- 推論:SwiftData 的 `@Model` 同時是持久化模型與可觀察物件，如果將來要加離線快取，應該把它當作 Infrastructure 的 persistence model,不要拿來當 Domain entity。
- **Token 存 Keychain:**
  - Apple 文件說 keychain 是「the best place to store small secrets, like passwords and cryptographic keys」([Storing keys in the keychain](https://developer.apple.com/documentation/security/storing-keys-in-the-keychain));generic password 的存取方式見 [Adding a password to the keychain](https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain)。
  - accessibility 可以選 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`:重開機後要解鎖一次才能讀，而且項目不會遷移到新裝置([文件](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly))。
  - 推論：因為 token 30 天就過期且沒有 refresh,不跟著備份遷移反而合理;換機後重新登入即可。
- **第三方 Keychain wrapper:不需要。** 依套件政策，第一方的 Security framework 做得到。
  - [KeychainAccess](https://github.com/kishikawakatsumi/KeychainAccess):最後 release v4.2.2(2021),最後 push 2024-05。
  - [keychain-swift](https://github.com/evgenyneu/keychain-swift):最後 push 2024-05。
  - [square/Valet](https://github.com/square/Valet):仍活躍,5.1.1(2026-09-09)。
  - 推論:Keychain 的操作只有存、取、刪三個，包成約 50 行的 `KeychainTokenStore` 即可。
- **非敏感偏好:`UserDefaults`**,例如上次選的「視角」。文件指明它用於「nonsensitive information」([UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults))。
- **HTTP 快取:** `URLSessionConfiguration.ephemeral` 不把快取、cookie、憑證寫入磁碟([ephemeral](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral))。推論：記帳資料屬於個人財務資訊，建議 APIClient 用 ephemeral configuration(認證走 Bearer header,不靠 cookie)。

---

## 6. 網路層

### 6.1 URLSession + Codable(建議)

- `URLSession.data(for:delegate:) async throws -> (Data, URLResponse)`,iOS 15 起可用([文件](https://developer.apple.com/documentation/foundation/urlsession/data(for:delegate:)))。另見 [WWDC21 Use async/await with URLSession](https://developer.apple.com/videos/play/wwdc2021/10095/)、[JSONDecoder](https://developer.apple.com/documentation/foundation/jsondecoder)、[Encoding and Decoding Custom Types](https://developer.apple.com/documentation/foundation/encoding-and-decoding-custom-types)。
- 建議的 APIClient 職責(推論，依據第 1.2 節的後端形狀):
  1. 從 `TokenStore` 取 token,帶上 `Authorization: Bearer`,不使用 `?token=`。
  2. 用泛型 `Envelope<T: Decodable>` 解 `{success, data, error}`;`success == false` 時轉成 domain 可理解的錯誤。
  3. 收到 401 時清除 token,並通知 `SessionModel` 回到登入畫面。
  4. DTO 只放在 Infrastructure,由 repository 實作轉成 Domain 型別，避免後端欄位命名滲進 Domain。
- 測試:`URLProtocol` 子類別可以攔截請求並回傳預先準備的回應([URLProtocol](https://developer.apple.com/documentation/foundation/urlprotocol))。搭配 `URLSessionConfiguration.protocolClasses` 就能在不連網的情況下測 Infrastructure(推論)。

### 6.2 Alamofire

- 5.12.2(2026-09-10),42,417★,MIT,runtime 相依 0。支援 Swift Concurrency,最低 Swift 6.0 / Xcode 16([README](https://github.com/Alamofire/Alamofire)、[Package.swift @5.12.2](https://github.com/Alamofire/Alamofire/blob/5.12.2/Package.swift),附 `Package@swift-6.3.swift` 等 fallback)。
- 推論：它的附加價值在 retry / interceptor、multipart、上傳下載進度這類功能，本專案 v1 用不到;依套件政策，第一方做得到就不引入。

### 6.3 第三方套件在 Xcode 26.6(Swift 6.3)下能否解析

我逐一檢查了各套件最新 tag 的 manifest(GitHub contents API):

| 套件 @tag | `Package.swift` 的 tools-version | 6.3 以下可用的 fallback manifest |
|---|---|---|
| TCA @1.26.2 | 6.4 | `Package@swift-6.1.swift` |
| swift-dependencies @1.17.1 | 6.4 | `Package@swift-6.0.swift`、`Package@swift-6.3.swift` |
| Alamofire @5.12.2 | 6.4 | `@swift-6.0` / `6.1` / `6.2` / `6.3` |
| Factory @3.4.1 | 6.1 | 不需要 |
| swift-openapi-generator @1.13.1、swift-openapi-urlsession @1.3.1 | 6.1 | 不需要 |
| Valet @5.1.1 | 6.0 | 不需要 |

推論：主流套件都已經以 Swift 6.4 為主線，同時保留 6.3 的 fallback。短期內沒有問題，但 Xcode 26.6 的支援窗口會隨時間縮短。

### 6.4 Apple swift-openapi-generator

- Apple 開源(不屬於 SDK),1.13.1(2026-09-01),Apache-2.0。它是 build-time 的 SwiftPM plugin,從 OpenAPI 3.0 / 3.1 文件產生 client([README](https://github.com/apple/swift-openapi-generator);[WWDC23 Meet Swift OpenAPI Generator](https://developer.apple.com/videos/play/wwdc2023/10171/))。
- runtime 相依:swift-openapi-runtime、swift-openapi-urlsession、swift-http-types、swift-collections([swift-openapi-urlsession Package.swift](https://github.com/apple/swift-openapi-urlsession/blob/1.3.1/Package.swift))。
- 不採用的原因：後端沒有 OpenAPI 文件(第 1.2 節),而後端凍結不能改。iOS 端自己手寫一份 spec 等於多維護一份會漂移的契約(推論)。如果 web 端將來補上 OpenAPI,它會是第一優先的替代方案(推論)。

### 6.5 Moya

- 最後 release 15.0.3(2022-08-12)([API](https://api.github.com/repos/Moya/Moya/releases)),而且架在 Alamofire 之上(未查證目前版本的相依)。排除。

---

## 7. 測試

### 7.1 Swift Testing(unit / integration)

- XCTest 文件的 Tip 原文:「Consider using Swift Testing for new unit test development … A test target can contain tests using both Swift Testing and XCTest, however don't mix API from the two frameworks in the same test. Continue to use XCTest for user interface tests and performance tests.」([XCTest](https://developer.apple.com/documentation/xctest))
- 功能與 Swift 版本對照([swift-evolution/proposals/testing](https://github.com/swiftlang/swift-evolution/tree/main/proposals/testing)):
  - Swift 6.1:test scoping traits(ST-0007)。
  - Swift 6.2:exit tests(ST-0008)、attachments(ST-0009)。
  - Swift 6.3:test cancellation(ST-0016)、issue severity warning(ST-0013)、image attachments(ST-0014 / 0017)。
  - **Swift 6.4 才有** Swift Testing / XCTest 的 targeted interoperability(ST-0021)與 per-test-case repetitions(ST-0024)。Xcode 27 release notes 也把互通設定列為 Xcode 27 的新功能([Xcode 27 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes))。
  - Apple 的 [Migrating a test from XCTest](https://developer.apple.com/documentation/testing/migratingfromxctest) 已經寫進互通功能。推論：那是對應新工具鏈的內容,Xcode 26.6 不適用。
- Xcode 26 帶來 exit tests、attachments、執行期 issue 偵測與新的 UI test 錄製體驗([Xcode 26 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes))。
- 入門見 [Meet Swift Testing (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10179/)、[Go further with Swift Testing (WWDC24)](https://developer.apple.com/videos/play/wwdc2024/10195/)。
- 分層測試策略(推論):
  - Domain:純函式與 value object,搭配 parameterized test([Implementing parameterized tests](https://developer.apple.com/documentation/testing/parameterizedtesting));在 macOS host 用 `swift test` 跑。
  - Application:注入 fake repository,測試 use case 的流程。
  - Infrastructure:用 `URLProtocol` stub 測 envelope 解碼、401 處理、DTO → Domain 的對映。
  - Presentation:`@MainActor` 的 Swift Testing test,直接實例化畫面 model、注入 fake use case,驗證狀態轉移。有需要時可以用 `Observations` 觀察狀態序列([Observations](https://developer.apple.com/documentation/observation/observations))。

### 7.2 XCTest + XCUIAutomation(UI test)

- UI 自動化 API 已經獨立成 XCUIAutomation framework(文件標示 Xcode 16.3 起),UI test 仍然用 XCTest 撰寫([XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation))。錄製流程是在 `XCTestCase` 的 test 方法中按下 record([Recording UI automation for testing](https://developer.apple.com/documentation/xcuiautomation/recording-ui-automation-for-testing))。
- WWDC25:
  - 「When you import XCTest, a framework called XCUIAutomation is automatically included.」
  - 建議用 `accessibilityIdentifier` 穩定定位元素。
  - test plan 可以設多種語系等 configuration,失敗時的 test report 附有影片。
  - 以上見 [Record, replay, and review: UI automation with Xcode](https://developer.apple.com/videos/play/wwdc2025/344/)。
- 推論:UI test 慢而且容易不穩定，只保留幾條關鍵流程(登入 → 儀表板、新增交易、切換視角)。iPhone 與 iPad 各用一個 test plan configuration。後端凍結，所以 UI test 應在 app 內以 launch argument 切換成 stub 的 Infrastructure,不打正式 API。

---

## 8. 推薦組合總覽

| 面向 | 選擇 | 一句理由 |
|---|---|---|
| 架構模式 | Apple 資料流 + 每畫面一個 `@MainActor @Observable` 畫面 model,少數 app 層級 model 放 Environment | 全部是第一方 API、0 相依;TCA 官方自承不擅長 JSON reader 型 app,而且 2.0 正在大改 |
| DDD 分層落地 | 一個 SwiftPM local package、多個 target(切法以 DDD 研究 4.1 為準),app target 只做組裝 | 相依方向由編譯器強制，對應 .NET 的分專案做法 |
| DI | initializer 注入 + `App` 裡的 composition root + `Environment`(`@Entry` / `.environment(obj)`) | 相依寫在型別簽章上，看得到也好追;規模小，不需要 container |
| 專案管理 | `.xcodeproj`(buildable folders)+ local package;不用 XcodeGen / Tuist | Apple 官方說法:buildable folders 可減少 `.pbxproj` diff 與衝突;少一道工具鏈,Xcode MCP 能直接開專案 |
| 網路 | URLSession async/await + Codable + ephemeral configuration,自寫薄 APIClient | 第一方就夠用;後端沒有 OpenAPI 文件，所以不走 generator |
| 持久化 | 不用 SwiftData / Core Data;JWT 存 Keychain(Security framework);偏好設定存 UserDefaults | v1 沒有離線需求;依政策，第一方 Keychain 做得到 |
| 測試 | Swift Testing(各層)+ XCTest / XCUIAutomation(少量 UI 流程) | 符合 Apple 對兩個框架的分工;Xcode 26.6 沒有互通，所以分 target |
| Concurrency | app target 預設 MainActor;package 預設 nonisolated;Domain 型別做成 `Sendable` value type | 對齊 Xcode 26 預設與 SE-0466,讓跨 actor 傳遞時零摩擦 |

---

## 9. GitHub 活躍度原始數據

查詢時間:2026-09-28 00:34(UTC+8)。欄位取自 `https://api.github.com/repos/<owner>/<repo>`(`stargazers_count`、`pushed_at`、`archived`、`license.spdx_id`),最新 release 取自 `…/releases`。所有 repo 的 `archived` 都是 `false`。

| Repo | ★ | pushed_at | License | 最新 release(發布日) | API |
|---|---|---|---|---|---|
| pointfreeco/swift-composable-architecture | 14,937 | 2026-09-18 | MIT | 1.26.2(2026-08-28);舊版本線 1.23.3(2026-09-18) | [repo](https://api.github.com/repos/pointfreeco/swift-composable-architecture) · [releases](https://api.github.com/repos/pointfreeco/swift-composable-architecture/releases) |
| pointfreeco/swift-dependencies | 2,195 | 2026-08-28 | MIT | 1.17.1(2026-08-28) | [repo](https://api.github.com/repos/pointfreeco/swift-dependencies) · [releases](https://api.github.com/repos/pointfreeco/swift-dependencies/releases) |
| pointfreeco/swift-navigation(TCA 相依) | 2,289 | 2026-09-04 | MIT | 2.11.2(2026-08-31) | [repo](https://api.github.com/repos/pointfreeco/swift-navigation) |
| pointfreeco/swift-sharing(TCA 相依) | 802 | 2026-09-24 | MIT | 2.10.1(2026-08-31) | [repo](https://api.github.com/repos/pointfreeco/swift-sharing) |
| pointfreeco/swift-perception(TCA 相依) | 808 | 2026-08-30 | MIT | — | [repo](https://api.github.com/repos/pointfreeco/swift-perception) |
| hmlongco/Factory | 2,904 | 2026-09-25 | MIT | 3.4.1(2026-09-25) | [repo](https://api.github.com/repos/hmlongco/Factory) · [releases](https://api.github.com/repos/hmlongco/Factory/releases) |
| Swinject/Swinject | 6,709 | 2025-09-01 | MIT | 2.10.0(2025-09-01);3.0.0-rc-2 為 prerelease | [repo](https://api.github.com/repos/Swinject/Swinject) |
| hmlongco/Resolver(已棄用) | 2,214 | 2026-06-30 | MIT | 1.5.1(2024-04-12) | [repo](https://api.github.com/repos/hmlongco/Resolver) |
| uber/needle | 2,017 | 2026-04-29 | Apache-2.0 | v0.25.1(2024-09-06) | [repo](https://api.github.com/repos/uber/needle) |
| tuist/tuist | 5,815 | 2026-09-27 | NOASSERTION(CLI 為 MIT) | CLI 4.209.0(2026-09-21);另有 4.211.0-canary | [repo](https://api.github.com/repos/tuist/tuist) · [releases](https://api.github.com/repos/tuist/tuist/releases) |
| yonaskolb/XcodeGen | 8,804 | 2026-09-13 | MIT | 2.46.0(2026-07-16) | [repo](https://api.github.com/repos/yonaskolb/XcodeGen) · [releases](https://api.github.com/repos/yonaskolb/XcodeGen/releases) |
| Alamofire/Alamofire | 42,417 | 2026-09-14 | MIT | 5.12.2(2026-09-10) | [repo](https://api.github.com/repos/Alamofire/Alamofire) · [releases](https://api.github.com/repos/Alamofire/Alamofire/releases) |
| Moya/Moya | 15,355 | 2026-07-14 | MIT | 15.0.3(2022-08-12) | [repo](https://api.github.com/repos/Moya/Moya) |
| apple/swift-openapi-generator | 1,975 | 2026-09-25 | Apache-2.0 | 1.13.1(2026-09-01) | [repo](https://api.github.com/repos/apple/swift-openapi-generator) · [releases](https://api.github.com/repos/apple/swift-openapi-generator/releases) |
| apple/swift-openapi-urlsession | 217 | 2026-09-25 | Apache-2.0 | 1.3.1(2026-06-23) | [repo](https://api.github.com/repos/apple/swift-openapi-urlsession) |
| swiftlang/swift-testing | 2,171 | 2026-09-27 | Apache-2.0 | swift-6.4.0-RELEASE(2026-09-15);swift-6.3.2-RELEASE(2026-05-13) | [repo](https://api.github.com/repos/swiftlang/swift-testing) · [releases](https://api.github.com/repos/swiftlang/swift-testing/releases) |
| square/workflow-swift | 373 | 2026-09-10 | Apache-2.0 | v6.0.1(2026-08-25) | [repo](https://api.github.com/repos/square/workflow-swift) |
| spotify/Mobius.swift | 583 | 2026-08-05 | Apache-2.0 | 0.8.0(2026-08-05) | [repo](https://api.github.com/repos/spotify/Mobius.swift) |
| uber/RIBs-iOS | 193 | 2026-07-12 | Apache-2.0 | 1.1.0(2026-07-12) | [repo](https://api.github.com/repos/uber/RIBs-iOS) |
| ReSwift/ReSwift | 7,588 | 2024-04-22 | MIT | 6.1.1(2023-01-06) | [repo](https://api.github.com/repos/ReSwift/ReSwift) |
| ReactorKit/ReactorKit | 2,784 | 2026-05-07 | MIT | 3.2.0(2022-01-13) | [repo](https://api.github.com/repos/ReactorKit/ReactorKit) |
| DevYeom/OneWay | 109 | 2026-06-03 | MIT | 3.1.0(2026-06-03) | [repo](https://api.github.com/repos/DevYeom/OneWay) |
| nalexn/clean-architecture-swiftui(範例 app) | 6,605 | 2025-07-14 | MIT | 3.0(2024-12-08) | [repo](https://api.github.com/repos/nalexn/clean-architecture-swiftui) |
| square/Valet | 4,171 | 2026-09-09 | Apache-2.0 | 5.1.1(2026-09-09) | [repo](https://api.github.com/repos/square/Valet) |
| kishikawakatsumi/KeychainAccess | 8,253 | 2024-05-31 | MIT | v4.2.2(2021-03-01) | [repo](https://api.github.com/repos/kishikawakatsumi/KeychainAccess) |
| evgenyneu/keychain-swift | 3,012 | 2024-05-26 | MIT | 沒有 GitHub release(最新 tag 24.0.0) | [repo](https://api.github.com/repos/evgenyneu/keychain-swift) |

---

## 10. 未查證與不確定的項目

1. **Xcode 26.6 拿不到 lazy `@State`**:「macro 屬於編譯期功能，所以要 Xcode 27 SDK」是推論;Apple 只說行為回溯到 iOS 17([WWDC26 269](https://developer.apple.com/videos/play/wwdc2026/269/)),沒有明說需要哪一版 Xcode。
2. **TCA 2.0**:正式發布日期、最低 iOS / Swift 版本、正式版是否仍為 MIT、何時開放給非付費使用者：公開文章都沒有寫。
3. **Xcode 16 起新專案範本是否預設 buildable folders**:release notes 只寫了 New Group 預設帶資料夾，範本的預設值未查證。
4. **Apple 對 MVVM 的立場**:目前查到的明文只有 WWDC26 Group Lab 的「架構中立」回答([8006](https://developer.apple.com/videos/play/wwdc2026/8006/))。Group Lab 是問答形式，不是正式的設計指引;沒有窮舉所有 WWDC session。
5. **tuist.dev 官方文件站**:對自動化抓取回傳 Cloudflare challenge,改引 repo 內的文件原始檔(`server/priv/docs`)。Tuist 雲端功能(cache、selective testing)的收費方式未查證;本文建議不用 Tuist,所以不影響結論。
6. **TCA / swift-dependencies 帶進 swift-syntax 對建置時間與 CI 時間的影響**:未量測、未查證。
7. **Factory README 提到的 Swift 6.2 nonisolated 限制在 Swift 6.3 是否仍存在**:README 沒有更新版本說明，未查證。
8. **Moya 目前版本的相依**:未查證(只查了 release 日期)。
9. **Swift Testing / XCTest 互通的文件範圍**:Apple 的 [Migrating a test from XCTest](https://developer.apple.com/documentation/testing/migratingfromxctest) 已描述互通功能，但 ST-0021 標示 Swift 6.4 才實作。「Xcode 26.6 不支援」是依 proposal 狀態推得，沒有在 Xcode 26.6 實機驗證。
10. **後端行為**:只讀了 `43a205d` 的程式碼，沒有打實際 API。CORS 對原生 app 沒有影響;錯誤訊息是中文字串，不是錯誤碼，iOS 端是否要依字串判斷錯誤類型，要看 DDD / 錯誤處理設計決定。
11. **學習成本與 DDD 相容性的評分**:比較表中這兩欄全部是推論，沒有一手來源。

---

## 參考來源(一手)

**Apple 文件**

- [Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [Observation](https://developer.apple.com/documentation/observation)
- [Observations](https://developer.apple.com/documentation/observation/observations)
- [Migrating from the Observable Object protocol to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)
- [Environment](https://developer.apple.com/documentation/swiftui/environment)
- [Entry()](https://developer.apple.com/documentation/swiftui/entry())
- [State](https://developer.apple.com/documentation/swiftui/state)
- [Bindable](https://developer.apple.com/documentation/swiftui/bindable)
- [NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack)
- [Managing files and folders in your Xcode project](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project)
- [Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)
- [Giving external agents access to Xcode](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode)
- [URLSession.data(for:delegate:)](https://developer.apple.com/documentation/foundation/urlsession/data(for:delegate:))
- [URLSessionConfiguration.ephemeral](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/ephemeral)
- [URLProtocol](https://developer.apple.com/documentation/foundation/urlprotocol)
- [JSONDecoder](https://developer.apple.com/documentation/foundation/jsondecoder)
- [Encoding and Decoding Custom Types](https://developer.apple.com/documentation/foundation/encoding-and-decoding-custom-types)
- [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)
- [Keychain services](https://developer.apple.com/documentation/security/keychain-services)
- [Storing keys in the keychain](https://developer.apple.com/documentation/security/storing-keys-in-the-keychain)
- [Adding a password to the keychain](https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain)
- [kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)
- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [Swift Testing](https://developer.apple.com/documentation/testing)
- [Migrating a test from XCTest](https://developer.apple.com/documentation/testing/migratingfromxctest)
- [Implementing parameterized tests](https://developer.apple.com/documentation/testing/parameterizedtesting)
- [XCTest](https://developer.apple.com/documentation/xctest)
- [XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation)
- [Recording UI automation for testing](https://developer.apple.com/documentation/xcuiautomation/recording-ui-automation-for-testing)

**Apple release notes**

- [Xcode 16](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes)
- [Xcode 26](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes)
- [Xcode 26.3](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_3-release-notes)
- [Xcode 26.6](https://developer.apple.com/documentation/xcode-release-notes/xcode-26_6-release-notes)
- [Xcode 27](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)

**WWDC**

- [WWDC23 Discover Observation in SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10149/)
- [WWDC25 Explore concurrency in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/266/)
- [WWDC25 Embracing Swift concurrency](https://developer.apple.com/videos/play/wwdc2025/268/)
- [WWDC25 Record, replay, and review: UI automation with Xcode](https://developer.apple.com/videos/play/wwdc2025/344/)
- [WWDC26 What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/)
- [WWDC26 Xcode, agents, and you](https://developer.apple.com/videos/play/wwdc2026/259/)
- [WWDC26 SwiftUI Group Lab](https://developer.apple.com/videos/play/wwdc2026/8006/)
- [WWDC24 Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/)
- [WWDC24 Go further with Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10195/)
- [WWDC21 Use async/await with URLSession](https://developer.apple.com/videos/play/wwdc2021/10095/)
- [WWDC23 Meet Swift OpenAPI Generator](https://developer.apple.com/videos/play/wwdc2023/10171/)

**swift.org / swift-evolution**

- [Swift 6.2 Released](https://www.swift.org/blog/swift-6.2-released/)
- [SE-0395 Observation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md)
- [SE-0466 Control default actor isolation inference](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)
- [SE-0475 Transactional Observation of Values](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md)
- [Swift Testing proposals(ST-0001~0029)](https://github.com/swiftlang/swift-evolution/tree/main/proposals/testing)
- [swift-migration-guide: EnableDataRaceSafety](https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/EnableDataRaceSafety.md)
- [swift test(SwiftPM docs)](https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/swifttest/)

**框架官方 repo 與文件**

- TCA:[README](https://github.com/pointfreeco/swift-composable-architecture)、[Package.swift @1.26.2](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Package.swift)、[FAQ @1.26.2](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Sources/ComposableArchitecture/Documentation.docc/Articles/FAQ.md)、release [1.24.0](https://github.com/pointfreeco/swift-composable-architecture/releases/tag/1.24.0) / [1.25.0](https://github.com/pointfreeco/swift-composable-architecture/releases/tag/1.25.0) / [1.26.0](https://github.com/pointfreeco/swift-composable-architecture/releases/tag/1.26.0)、[Point-Free: Beta Preview ComposableArchitecture 2.0](https://www.pointfree.co/blog/posts/206-beta-preview-composablearchitecture-2-0)
- swift-dependencies:[README](https://github.com/pointfreeco/swift-dependencies)、[Designing dependencies](https://github.com/pointfreeco/swift-dependencies/blob/main/Sources/Dependencies/Documentation.docc/Articles/DesigningDependencies.md)
- Factory:[README](https://github.com/hmlongco/Factory)、[3.4.0 release](https://github.com/hmlongco/Factory/releases/tag/3.4.0)
- Resolver:[README](https://github.com/hmlongco/Resolver)
- Tuist:[Generated projects](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/features/projects.md)、[buildable folders changelog](https://github.com/tuist/tuist/blob/main/server/priv/marketing/changelog/2025.08.11-buildable-folders.md)、[Install Tuist](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/install-tuist.md)、[LICENSE.md](https://github.com/tuist/tuist/blob/main/LICENSE.md)
- XcodeGen:[README](https://github.com/yonaskolb/XcodeGen)、[CHANGELOG](https://github.com/yonaskolb/XcodeGen/blob/master/CHANGELOG.md)
- Alamofire:[README](https://github.com/Alamofire/Alamofire)
- swift-openapi-generator:[README](https://github.com/apple/swift-openapi-generator)
- GitHub Actions:[runner-images macos-26-arm64](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- 後端:[onion523/my-money @ 43a205d](https://github.com/onion523/my-money/tree/43a205d4366337fbec9d672cfc49e27b4f2cf48c)
