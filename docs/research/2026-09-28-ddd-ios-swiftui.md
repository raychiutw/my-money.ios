# 原生 iOS（SwiftUI）如何採用 Domain-Driven Design：my-money.ios 研究

查核日期：2026-09-28。

查核範圍與方法：

- **DDD 定義**：Eric Evans《Domain-Driven Design Reference》（2015，CC BY 4.0 PDF）。文中頁碼一律用**書內頁碼**，連結的 `#page=` 指到對應的 PDF 頁。Martin Fowler bliki 條目皆由 Fowler 本人撰寫。Vaughn Vernon 只查到他 2011 年的《Effective Aggregate Design》系列文章；*Implementing Domain-Driven Design* 一書內容**未查證**。
- **Apple／Swift**：developer.apple.com 文件（透過 DocC JSON 讀全文）、docs.swift.org 的 TSPL 與 SwiftPM 文件、swift-evolution 提案原文、swift-foundation 原始碼、WWDC 逐字稿，以及 Apple 官方 sample repo（固定 commit）。
- **後端與 web client 的事實**：唯讀查看 [`onion523/my-money` @ `43a205d`](https://github.com/onion523/my-money/tree/43a205d4366337fbec9d672cfc49e27b4f2cf48c)，只用來核對 wire 格式與 web 端規則，沒有修改。
- **本機實測**：Xcode 26.6（17F113）、Swift 6.3.3，在 macOS 26 host 上用 SwiftPM CLI 建置、測試實驗用 package（放在 `/tmp`，不在任何 repo 裡）。**沒有在 iOS 模擬器或實機上執行，也沒有建立 Xcode app 專案**。凡標「實測」的，都是 macOS host 上 Foundation 與編譯器的行為。
- 標示方式：〔定義〕= Evans／Fowler 原文；〔Apple 文件〕= Apple 與 Swift 專案的一手文件、提案、WWDC、官方 sample；〔實測〕= 本機實驗的輸出；〔推論〕= 我的工程判斷。第 4 節全部是推論。

## 結論

1. **〔定義＋推論〕iOS 是凍結後端的 downstream。套 Evans 的定義，Partnership、Shared Kernel、Customer/Supplier 三種關係都不成立，只剩 Conformist 和 Anticorruption Layer 可以選。** Customer/Supplier 的前提是「downstream priorities factor into upstream planning」，Partnership 要求雙方協調規劃、共同演進介面，Shared Kernel 要共享模型子集和程式碼。後端凍結後，這三個條件都做不到。[Customer/Supplier p.32](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=39)、[Partnership p.30](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=37)、[Shared Kernel p.31](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=38)
2. **〔推論〕建議做法：模型語意採 Conformist，只在一個 seam 上做薄的表示層翻譯（形式像 ACL，內容是 Conformist）。** 不重新建模，也不在本地重算任何規則，這樣才守得住「與 web 完全對等」。wire 上的怪癖（key 大小寫混用、0/1 與 true/false 並存、envelope、`balance` 一詞兩義、REAL 浮點）全部收在 Infrastructure 這一層吸收。Evans 在 Open-host Service 一節明寫，同一個上游的 client「some of them will be conformist and some will build anticorruption layers」。[OHS p.35](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=42)。後端凍結同時消掉了 Conformist 最大的代價（上游改版外溢到下游），也消掉了 ACL 最大的好處（隔離上游演進）。剩下支持翻譯層的理由只有兩個：locality 和型別清晰。
3. **〔定義＋推論〕戰術構件的取捨：** Value Object 是 thin client 裡最有價值的構件。Entity 用 server 擁有的 ID 來識別。Repository 當成測試 seam。Domain Service 只用來當「伺服器計算結果」的介面。Aggregate 不實作，只保留「尊重伺服器的一致性邊界、彼此只用 ID 參照」這條紀律。Domain Event 和獨立的 Factory 物件**刻意不用**。定義見第 2 節表格。
4. **〔Apple 文件＋實測〕金額用 `Decimal`，而且絕對不能經過 `Double`。** `Decimal` 是 `Sendable`／`Hashable`／`Codable`；Apple 自己的 Food Truck 範例也用 `grandTotal: Decimal`。JSONDecoder 會直接從 JSON 文字解析出 `Decimal`：實測 `1234.56` 解出來是精確的 `1234.56`。但 `Decimal(Double)` 或浮點字面值 `let x: Decimal = 1234.56` 會得到 `1234.5599999999997952`。後端 SQLite REAL 是 8-byte IEEE 浮點數，加總也是在 JS 端 `reduce` 或 SQL `SUM` 算的，所以 ACL 必須明訂正規化規則。[Decimal](https://developer.apple.com/documentation/foundation/decimal)、[init(floatLiteral:)](https://developer.apple.com/documentation/foundation/decimal/init(floatliteral:))、[Order.swift](https://github.com/apple/sample-food-truck/blob/3954a769e99f3cc53297d94f2b960ceb2665b3d6/FoodTruckKit/Sources/Order/Order.swift)、[SQLite REAL](https://www.sqlite.org/datatype3.html)
5. **〔Apple 文件＋實測〕顯示格式必須對齊 web 的捨入方式。** Foundation currency FormatStyle 的 `rounded(rule:)` 預設是 `.toNearestOrEven`，web 用的 `Intl.NumberFormat` 預設是 `halfExpand`。實測 2.5 元在 iOS 預設顯示 `$2`、在 web 顯示 `$3`。要加 `.rounded(rule: .toNearestOrAwayFromZero)` 才會一致。[rounded(rule:increment:)](https://developer.apple.com/documentation/foundation/decimal/formatstyle/currency/rounded(rule:increment:))、[ECMA-402 SetNumberFormatDigitOptions](https://tc39.es/ecma402/#sec-setnfdigitoptions)、[web formatCurrency](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/components/utils.ts#L1-L8)
6. **〔Apple 文件〕Entity 用 `struct` 加 `Identifiable`，不用 class。** Apple 明寫：identity 由遠端資料庫擁有時，「you can model records as structures with identifiers」。[Choosing Between Structures and Classes](https://developer.apple.com/documentation/swift/choosing-between-structures-and-classes)
7. **〔Apple 文件＋實測〕Domain module 維持 nonisolated（SwiftPM 的預設），所有 public 型別明確標 `Sendable`；UI module 才開 `defaultIsolation(MainActor.self)`。** WWDC25 建議 main actor 預設「primarily for your main app module and any modules that are focused on UI interactions」；SE-0466 也說 MainActor 是 library 的錯誤預設。實測結果：Domain 若開 MainActor 預設，Infrastructure 裡 nonisolated 的翻譯程式碼就無法同步建構 `Money`。另外，public struct 不會隱式取得 `Sendable`。[WWDC25 268](https://developer.apple.com/videos/play/wwdc2025/268/)、[SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)、[Sendable](https://developer.apple.com/documentation/swift/sendable)
8. **〔Apple 文件＋實測〕`@Observable` 只放在 Features 層的 `@MainActor` store class 上，domain model 本身不是 `@Observable`。** 實測有兩個編譯錯誤可佐證：這個巨集不能套在 struct 上；在 nonisolated module 裡宣告的 `@Observable` class 不是 Sendable。Apple 的 Food Truck 範例也是同樣做法：value type 資料放進一個 observable model 物件。[Managing model data](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)、[FoodTruckModel.swift](https://github.com/apple/sample-food-truck/blob/3954a769e99f3cc53297d94f2b960ceb2665b3d6/FoodTruckKit/Sources/Model/FoodTruckModel.swift)
9. **〔Apple 文件＋實測〕DTO 與 domain model 分開，DTO 在 Infrastructure 內設為 `internal`。** `convertFromSnakeCase` 不會動到 camelCase 的 key，所以能處理這個後端混用的 key。但它有兩個限制：`account_id` 只會變成 `accountId`，不會是 `accountID`；Bool 也無法從 0/1 解碼（實測得到 `typeMismatch`）。[convertFromSnakeCase](https://developer.apple.com/documentation/foundation/jsondecoder/keydecodingstrategy-swift.enum/convertfromsnakecase)
10. **〔Apple 文件＋實測〕用單一 local package、多個 target 切出 Domain／Infrastructure／Features。依賴方向寫在 `Package.swift`，但 CI 一定要加 `--explicit-target-dependency-import-check error`。** 實測：沒宣告依賴的 `import`，乾淨建置時會失敗，增量建置時卻會通過；加上這個旗標後就穩定報錯。另外 `package` 存取只在同一個 SwiftPM package 內有效。Xcode app target 預設不在 local package 裡（推論，未實測 Package Access Identifier 設定），所以 App 要用的東西必須是 `public`。[SE-0386](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0386-package-access-modifier.md)、[swift build](https://docs.swift.org/latest/documentation/packagemanagerdocs/swiftbuild/)
11. **〔Apple 文件〕測試：Domain、ACL、Features store 都用 Swift Testing（`@Test(arguments:)`、`#expect`、`#require`、隔離到 `@MainActor` 的測試）；UI 測試仍用 XCTest。** [Swift Testing](https://developer.apple.com/documentation/testing)、[Adding tests to your Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)
12. **〔Apple 文件＋推論〕Apple 官方範例確實用 local package 做模組化（Backyard Birds 拆成 Data 和 UI 兩個 package，Food Truck 用 FoodTruckKit），資料夾也以領域概念命名。但本次查到的文件和 WWDC 都沒有規定分層方式，更沒有提 DDD；WWDC26 SwiftUI Group Lab 甚至明說「there's really no architecture that we expect you to adopt」。** [Backyard Birds repo](https://github.com/apple/sample-backyard-birds/tree/1843d5655bf884b501e2889ad9862ec58978fdbe)、[WWDC26 8006](https://developer.apple.com/videos/play/wwdc2026/8006/)

## 1. 戰略設計

### 1.1 用到的定義

〔定義〕Evans 定義 bounded context 為「A description of a boundary (typically a subsystem, or the work of a particular team) within which a particular model is defined and applicable」；ubiquitous language 是「used by all team members within a bounded context」。[Definitions p.vi](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=6)

Bounded Context 模式本身要求「Explicitly set boundaries in terms of team organization, usage within specific parts of the application, and physical manifestations such as code bases and database schemas」，並「Apply Continuous Integration to keep model concepts and terms strictly consistent within these bounds」。[Bounded Context p.2](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=9)

upstream–downstream 的定義是：upstream 的行為影響 downstream 的成敗，反過來則不然。「The upstream team may succeed independently of the fate of the downstream team.」[Context Mapping p.28](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=35)

Context Map 的要求是「Describe the points of contact between the models, outlining explicit translation for any communication … Map the existing terrain.」[Context Map p.29](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=36)

〔定義〕Fowler（2014）強調，不同 context 可以對同一個概念有完全不同的模型，要靠「mechanisms to map between these polysemic concepts for integration」；而且 DDD 認為「total unification of the domain model for a large system will not be feasible or cost-effective」。[Fowler: BoundedContext](https://martinfowler.com/bliki/BoundedContext.html)

### 1.2 iOS 是不是另一個 bounded context

〔推論〕是，而且它是 downstream。依據有三點：

- iOS 是另一個 code base、另一種語言，屬於 Evans 說的「physical manifestations」。
- iOS 不可能跟後端一起做 Continuous Integration，因為後端凍結、在另一個 repo。
- 後端的成敗不受 iOS 影響。

相較之下，web client 和後端在同一個 repo（`web/` 與 `backend/`），比較像同一個 context 內的兩個部分。這個判斷未查證他們的 CI。[repo 根目錄](https://github.com/onion523/my-money/tree/43a205d4366337fbec9d672cfc49e27b4f2cf48c)

### 1.3 逐一比對 Evans 的關係模式

| 關係模式 | Evans 的成立條件（摘） | my-money.ios 是否成立 | 採用的後果 |
|---|---|---|---|
| Partnership\* | 兩個 context「succeed or fail together」，需要「coordinated planning」，雙方共同演進介面。[p.30](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=37) | 否。後端凍結，無法共同規劃。 | — |
| Shared Kernel | 明確劃出雙方共享的模型子集「and associated code」，改動前要協商，並持續整合。[p.31](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=38) | 否。TypeScript 與 Swift 沒有共享程式碼，後端也不能改。 | — |
| Customer/Supplier | 「downstream priorities factor into upstream planning」；雙方共同開發的驗收測試可以加進 upstream 的 CI。[p.32](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=39) | 否。凍結就代表 downstream 的需求進不了 upstream 的規劃。 | — |
| Conformist | upstream 沒有動機滿足 downstream（這裡是連能力都沒有）；downstream「slavishly adhering to the model of the upstream team」，換來「enormously simplifies integration」，並與上游「share a ubiquitous language」。[p.33](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=40) | 是，條件完全吻合。 | 好處：零語意翻譯，對等最容易保證，與 web 和後端共用詞彙。代價：上游不佳的表示方式會直接散進 iOS 各處。 |
| Anticorruption Layer | 在 shared kernel、partner、customer/supplier 都做不到時使用。downstream 建立隔離層，「in terms of your own domain model」，必要時雙向翻譯，而且「little or no modification to the other system」。[p.34](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=41) | 「控制不足」這個條件吻合；但在對等的前提下，iOS 並沒有「自己的 domain model」。 | 好處：上游的怪癖集中在一處。代價：一旦翻譯成不同的模型，語意就會與 web 分岔；翻譯程式碼本身也要維護。 |
| Open-host Service | upstream 定義開放協定給所有整合方；「Each client is downstream, and typically some of them will be conformist and some will build anticorruption layers」。[p.35](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=42) | 用來描述上游的狀態：REST API 同時服務 web 和 iOS，實質上就是 OHS。但凍結後已經不能再「Enhance and expand」。 | 這不是 iOS 能做的選擇。 |
| Published Language | 以「well-documented shared language」作為交換媒介。[p.36](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=43) | 很弱。沒有正式文件，實際上的文件就是 [`types.ts`](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/types.ts) 和 [web `client.ts`](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/api/client.ts)。 | 〔推論〕iOS 端用 fixtures 加 `CONTEXT.md` 補成事實上的 PL。 |
| Separate Ways | 兩邊沒有重要關係，就完全切開。[p.37](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=44) | 否。iOS 的所有功能都依賴 API。 | — |

\* Evans 標注：「New term introduced since the 2004 book」。

### 1.4 結論：語意 Conformist，表示層薄翻譯

〔推論〕三個可行方案的後果比較：

| 方案 | 做法 | 好處 | 代價與風險 |
|---|---|---|---|
| 純 Conformist | DTO 就是 domain model，View 直接拿 wire 型別來用 | 程式最少，對等性由結構本身保證 | `type == "credit_card"`、`is_shared == 1` 這類判斷散進各個 View 和 store，locality 很差；每次測試都得從 JSON 起步 |
| **語意 Conformist＋薄翻譯層（建議）** | 概念、名稱、規則全部照搬上游；只在 Infrastructure 把 wire 表示翻成 Swift 型別，並拆開一詞兩義的欄位 | 怪癖只出現在一個 module；domain 型別用 UL 表達；沒有重算任何規則，對等性不受影響 | 需要映射程式碼。Fowler 引用 Randy Stafford 的話：DTO 映射的成本「significant, and it's painful」。[Fowler: LocalDTO](https://martinfowler.com/bliki/LocalDTO.html)。本案 API 資源大約 10 類，成本有上限 |
| 完整 ACL | iOS 建自己的豐富模型，餘額、預測等在本地重算 | 理論上最能表達 iOS 自己的觀點 | 直接違反「不增加也不修改」：規則重複一份，與 web 必然分岔。Evans 的 ACL 是為了保護「your own domain model」，iOS 並沒有這樣的模型 |

最關鍵的一點：**凍結讓 Conformist 的主要風險（上游模型改變，下游跟著被迫改）幾乎歸零。** 所以要不要做翻譯層，已經不是「隔離上游」的問題，而是 locality 的問題：wire 的怪癖要散在 N 個畫面，還是集中在一個 module。依照 deep module 的詞彙，這個翻譯層是一個小 interface（repository protocol）背後藏著大量表示層知識的 module，能通過 deletion test：刪掉它，複雜度會重新出現在所有呼叫端。

如果哪天後端解凍，關係可能轉成 Customer/Supplier。薄翻譯層能把那時的影響限縮在一個 module 內。

### 1.5 wire 實況（補充前提）

〔推論〕題目前提寫「wire format 是 snake_case、布林值用 0/1」。原始碼顯示實際情況更混雜，正好說明為什麼需要一層集中吸收：

| 事實 | 來源 | 對翻譯層的影響 |
|---|---|---|
| 資料表列用 snake_case（`account_id`、`credit_limit`、`is_shared`）；計算型 endpoint 回 camelCase（`bankTotal`、`ccBilled`、`willOverdraft`、`minBalance`）；camelCase 物件裡又巢狀 snake_case（`affectedGoals[].saved_amount`） | [types.ts](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/types.ts)、[accounts.ts L95](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/handlers/accounts.ts#L95)、[client.ts L179–281](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/api/client.ts#L179-L281) | `convertFromSnakeCase` 對 camelCase key 不做任何轉換，Apple 文件的例子是 `feeFiFoFum` 轉完仍是 `feeFiFoFum`，所以一個策略就能處理混用的 key |
| 布林值：資料庫旗標是 0/1（`is_shared: number`），計算出來的旗標是 JSON boolean（`over`、`willOverdraft`、`affectsSavings`） | [budgets.ts L20](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/handlers/budgets.ts#L20)、[forecast.ts L88–96](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/handlers/forecast.ts#L88-L96)；D1 文件：Boolean 寫入後讀回是 `0`／`1` 的 Number。[D1 type conversion](https://developers.cloudflare.com/d1/worker-api/) | 每個欄位要看來源決定解碼方式，這種知識只該寫在一個地方 |
| `balance` 一詞兩義：`bankTotal` 由 bank 的 `balance` 加總而得，`ccBilled` 由 credit_card 的 `balance` 加總而得 | [accounts.ts L79–82](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/handlers/accounts.ts#L79-L82) | 在 domain 裡拆成 `deposit`／`billed` 兩個名字 |
| 金額：SQLite REAL（「8-byte IEEE floating point number」），加總用 JS `reduce` 或 SQL `SUM(amount)` | [SQLite datatype3](https://www.sqlite.org/datatype3.html)、[budgets.ts L15](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/handlers/budgets.ts#L15) | 有非整數金額時，回傳值可能帶浮點尾數（推論，未在實際 API 觀察到） |
| envelope 是 `{ success: true; data: T } \| { success: false; error: string }`；ID 是字串 | [types.ts L122](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/types.ts#L122) | 泛型 `Envelope<T>`，typed ID 包 `String` |
| 範圍參數 `scope=all\|household\|personal`，過濾在伺服器端做 | [transactions.ts L10–28](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/handlers/transactions.ts#L10-L28) | client 只傳一個 enum，不在本地過濾 |
| web 的錯誤語意：`!res.ok \|\| !data.success` 就丟出 `data.error \|\| '請求失敗'`；非 `/auth/` 路徑收到 401 時清掉 token 並導回登入頁 | [client.ts L8–39](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/api/client.ts#L8-L39) | 為了對等，iOS 要照這個規則映射錯誤 |
| web 端自己保有的規則：`formatCurrency` 固定 zh-TW、TWD、0 位小數；`today()`／`thisMonth()` 用 `toISOString()`，也就是 **UTC 日期**；支出與收入分類清單、固定收支週期的標籤都是前端常數 | [utils.ts](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/components/utils.ts) | 這些是 iOS 要做到對等時，**唯一需要在 Swift 裡實作的「規則」** |

### 1.6 Ubiquitous Language 與 `CONTEXT.md`

〔定義〕Conformist 的附帶結果是「you will share a ubiquitous language with your upstream team」。[p.33](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=40)。Evans 同時要求「Recognize that a change in the language is a change to the model」。[Ubiquitous Language p.3–4](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=10)

〔推論〕因此 `CONTEXT.md` 的詞彙應該直接沿用後端和 web 的概念。iOS 自創的詞只限一種情況：拆開一詞兩義的欄位時。例如「存款餘額」與「已出帳金額」都對應 wire 的 `balance`，這層對應要在詞條裡寫明。這正是 Fowler 說的 polysemy 要有明確映射。[Fowler: BoundedContext](https://martinfowler.com/bliki/BoundedContext.html)。web 端的常數（分類清單、週期標籤）也屬於 language 的一部分。

### 1.7 Context map 草圖（推論）

```
┌──────────────────────────────────────────────┐
│ my-money backend（Hono / Workers / D1）       │  upstream：Open-host（REST + JSON）
│  規則擁有者：餘額、預測、消費檢查、家庭範圍、   │  沒有正式的 Published Language
│  預算超支                                     │
└───────────────┬───────────────────┬──────────┘
                │                   │
                ▼                   ▼
      web client（同 repo）     my-money.ios（凍結後才開始做）
      Conformist                語意 Conformist ＋ 薄翻譯層（MyMoneyAPI module）
```

## 2. 戰術設計：thin client 裡哪些構件有用

| 構件 | Evans 定義重點 | 在 my-money.ios 的用途 | 判定 |
|---|---|---|---|
| Value Object | 「When you care only about the attributes and logic of an element … Treat the value object as immutable. Make all operations Side-effect-free Functions」。[p.12](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=19) | `Money`、各種 typed ID、`AccountKind`、`TransactionKind`、`YearMonth`、`CalendarDay`、`ViewScope`、`SpendingVerdict`、`BillingCycle` | **採用（核心）** |
| Entity | 以 identity 而非屬性區分；「This means of identification may come from the outside」。[p.11](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=18) | Account、Transaction、RecurringItem、Goal、Budget、Household、HouseholdMember；ID 由後端產生 | **採用**（struct＋`Identifiable`） |
| Aggregate | 把 entity 和 value object 聚成一組，外部只能參照 root，由 root 負責不變條件，「Use the same aggregate boundaries to govern transactions」。[p.16](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=23) | 交易（transaction）和不變條件都由伺服器執行，client 無從保證 | **只保留紀律**：尊重伺服器資源邊界，彼此用 ID 參照 |
| Repository | 為需要全域存取的 aggregate root 提供「the illusion of an in-memory collection」，並以「criteria meaningful to domain experts」查詢。[p.17](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=24) | protocol 放在 Domain，URLSession adapter 放在 Infrastructure，另有 in-memory adapter 給測試 | **採用**（作為 seam） |
| Domain Service | 「When a significant process or transformation in the domain is not a natural responsibility of an entity or value object … declared as a service」。[p.14](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=21) | 30 天現金流預測、消費檢查：介面放在 Domain，實作是遠端呼叫 | **有限採用** |
| Domain Event\* | 「Something happened that domain experts care about」，並且要與「system events」區分。[p.13](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=20) | 後端沒有事件流；client 端「新增後重抓」屬於 system event | **刻意不用** |
| Factory | 「When creation of an entire, internally consistent aggregate, or a large value object, becomes complicated」。[p.18](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=25) | 建立由伺服器負責（ID 也是伺服器產生）；還原（reconstitution）由翻譯層處理 | **刻意不用**獨立的 Factory 物件 |
| Layered Architecture | 「Concentrate all the code related to the domain model in one layer and isolate it」；「“Hexagonal Architecture” may serve as well or better」。[p.10](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=17) | SwiftPM target：Domain 在中心，Infrastructure 依賴 Domain | **採用** |
| Modules | 「Choose modules that tell the story of the system … Give the modules names that become part of the ubiquitous language」（aka Packages）。[p.15](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=22) | Domain 內以概念分資料夾（Accounts、Transactions、Budgets …） | **採用** |

### 2.1 Value Object：thin client 最值得投資的地方

〔推論〕規則在伺服器上，但「怎麼解讀和呈現一個值」全都在 client：金額捨入、月份字串、帳戶種類決定 `balance` 的意義、`verdict` 的三種狀態。把這些做成 value object，才能符合 Evans 講的「Make it express the meaning of the attributes it conveys and give it related functionality」。

Supple Design 裡的 Side-Effect-Free Functions 說「All operations of a value object should be side-effect-free functions」。[p.21](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=28)。Closure of Operations 說「This pattern is most often applied to the operations of a value object」。[p.24](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=31)。`Money + Money -> Money` 就是這個模式的例子。

〔定義〕Fowler 指出，除了不可變之外，「ensuring assignments always make a copy」也能避免 aliasing 的 bug，並舉 C# struct 為例。[Fowler: ValueObject](https://martinfowler.com/bliki/ValueObject.html)。Swift struct 同樣是複製語意，見 3.1 節的 Apple 文件。

### 2.2 Entity：identity 由後端擁有

〔推論〕所有 ID 都由後端產生，而且是字串，見 [types.ts](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/backend/src/types.ts)。所以 Evans 的「identification may come from the outside」正好適用。iOS 不需要自己產生 identity，只需要讓型別系統把 `AccountID` 和 `TransactionID` 分開，避免 Evans 說的「Mistaken identity can lead to data corruption」。[p.11](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=18)

### 2.3 Aggregate：只留紀律，不實作 root

〔推論〕Aggregate 的主要價值是一致性邊界和交易邊界。這兩件事在 my-money 裡都由後端 D1 負責，client 沒有辦法強制，實作 aggregate root 的不變條件等於在重做伺服器的工作。要保留的只有兩件事：

1. **參照其他 aggregate 只用 ID。** Transaction 持有 `AccountID`，而不是 `Account` 物件。〔定義〕Vernon 的規則原文是「Prefer references to external aggregates only by their globally unique identity, not by holding a direct object reference」。他也承認，只用 ID 參照會讓「clients that assemble and render user interface views」需要一次查多個 repository。[Vernon 2011 Part II](https://www.dddcommunity.org/wp-content/uploads/files/pdf_articles/Vernon_2011_2.pdf)
2. **分清「可寫資源」和「伺服器算出來的讀取結果」**（推論）。Account、Transaction、RecurringItem、Goal、Budget、Household 是可寫資源；`/accounts/balance`、`/transactions/summary/*`、`/recurring/amortize`、`/forecast`、帶 `spent`／`over` 的預算列表都是伺服器計算的讀取結果。後者在 iOS 裡只是 value object，例如 `BalanceSummary`、`BudgetStatus`，不是 entity。

### 2.4 Repository：當 seam，不假裝是記憶體裡的集合

〔推論〕Evans 講「illusion of an in-memory collection」，但遠端 API 的每次呼叫都是 `async throws`，會有延遲、會有 401。不必假裝它是本地集合，protocol 只提供後端真的有的操作即可。重點在兩件事：

- 方法以 UL 命名，例如 `transactions(in: YearMonth, scope: ViewScope)`。
- 它是一個真的 seam：production 用 URLSession adapter，測試用 in-memory adapter，有兩個 adapter。套 deep module 的詞彙：「One adapter means a hypothetical seam. Two adapters means a real one.」

### 2.5 Domain Service：伺服器計算的介面

〔推論〕「30 天現金流預測」和「消費檢查」是 Evans 定義中「significant process … not a natural responsibility of an entity」的典型例子。只是計算在伺服器上做。Domain 宣告 `CashFlowForecasting` 這類介面，用 UL 寫下合約，例如「verdict 由伺服器判定，client 不得自行推導」。這是 Evans 說的「Define a service contract … State these assertions in the ubiquitous language」。[p.14](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=21)

### 2.6 Anemic 疑慮與 Core Domain

〔定義〕Fowler 批評 anemic domain model「incur all of the costs of a domain model, without yielding any of the benefits」，也說 domain model「is worthwhile iff you use the powerful OO techniques to organize complex logic」，以及「Domain Models aren't always the best tool」。他引用 Evans 對 application layer 的描述：「This layer is kept thin. It does not contain business rules or knowledge」。這句是 Evans 原書的話，經 Fowler 引用；原書頁碼未查證。[Fowler: AnemicDomainModel](https://martinfowler.com/bliki/AnemicDomainModel.html)

〔推論〕iOS 的 domain 型別「多半只是資料」，這不等於 Fowler 批評的反模式。反模式指的是把本該在 domain 物件裡的行為抽到 service 裡；這裡的行為根本不在 client，而在伺服器。真正要防的是另一種退化：在 store 或 View 裡寫 `if account.type == …`。這種邏輯要移回 value object 或 entity。

〔定義〕Evans 要求「Justify investment in any other part by how it supports the distilled core」。[Core Domain p.40](https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf#page=47)。〔推論〕整個系統的 core domain（預測、消費檢查）在後端。iOS 值得投資的地方是翻譯的正確性和對等的 UX，不是一個豐富的本地模型。

### 2.7 Fowler 對 DDD 本質的看法

〔定義〕Fowler 認為 Evans 最大的貢獻之一是 Strategic Design：「how to organize large domains into a network of Bounded Contexts」。他也說「the core notions of Domain-Driven Design are conceptual, and thus apply well with any programming approach」。[Fowler: DomainDrivenDesign](https://martinfowler.com/bliki/DomainDrivenDesign.html)。〔推論〕對 thin client 而言，這代表 DDD 的價值主要在第 1 節（context 關係和 UL），戰術構件只取有用的部分。

## 3. Swift／SwiftUI 的落地方式

### 3.1 Value Object：`struct` 加 `Equatable`／`Hashable`／`Sendable`

〔Apple 文件〕Apple 的建議是「Use structures by default」。因為 structure 是 value type，「local changes to a structure aren't visible to the rest of your app unless you intentionally communicate those changes」。[Choosing Between Structures and Classes](https://developer.apple.com/documentation/swift/choosing-between-structures-and-classes)

〔Apple 文件〕`Sendable` 的隱式推導只適用於「Structures and enumerations that aren't public and aren't marked `@usableFromInline`」，其他情況「you need to declare conformance to Sendable explicitly」。[Sendable](https://developer.apple.com/documentation/swift/sendable)。〔實測〕把 domain 放進獨立 module 後，型別必須是 `public`。沒標 `Sendable` 的 public struct 傳給 `T: Sendable` 會編譯錯誤：`type 'NotMarked' does not conform to the 'Sendable' protocol`。

〔Apple 文件〕public struct 的預設 memberwise init 是 internal，「you must provide a public memberwise initializer yourself」。[TSPL: Access Control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/)

以下程式碼已在本機用 Swift 6.3.3 編譯並通過測試：

```swift
// MyMoneyDomain（nonisolated、不 import SwiftUI）
import Foundation

public struct Money: Hashable, Comparable, Sendable {
    public let amount: Decimal                 // 新台幣元；單一幣別（待 ADR）
    public init(_ amount: Decimal) { self.amount = amount }
    public static let zero = Money(0)

    // Closure of Operations：Money 與 Money 運算仍得到 Money
    public static func + (l: Money, r: Money) -> Money { Money(l.amount + r.amount) }
    public static func - (l: Money, r: Money) -> Money { Money(l.amount - r.amount) }
    public static func < (l: Money, r: Money) -> Bool { l.amount < r.amount }

    /// 對齊 web 的 formatCurrency：zh-TW、TWD、0 位小數、ties away from zero
    public func formatted(locale: Locale = Locale(identifier: "zh_TW")) -> String {
        amount.formatted(.currency(code: "TWD").locale(locale)
            .precision(.fractionLength(0))
            .rounded(rule: .toNearestOrAwayFromZero))
    }
}
```

〔定義＋推論〕Fowler 的 value object 條目說「An amount of money consists of a number and a currency」。[Fowler: ValueObject](https://martinfowler.com/bliki/ValueObject.html)。web 把幣別寫死為 TWD，見 [utils.ts L1–8](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/components/utils.ts#L1-L8)，所以上面刻意不放 currency 欄位。這是難以逆轉的決定，應該寫 ADR。

### 3.2 金額：`Decimal` 還是整數分

〔Apple 文件〕`Decimal` 是「A structure representing a base-10 number」，符合 `Sendable`、`Hashable`、`Codable`、`Comparable`。[Decimal](https://developer.apple.com/documentation/foundation/decimal)。它可以表示「mantissa x 10^exponent where mantissa is a decimal integer up to 38 digits long」。[NSDecimalNumber](https://developer.apple.com/documentation/foundation/nsdecimalnumber)。

但它的 `init(floatLiteral value: Double)` 參數型別是 `Double`。[init(floatLiteral:)](https://developer.apple.com/documentation/foundation/decimal/init(floatliteral:))

〔Apple 文件〕swift-foundation 的 JSONDecoder 遇到 `Decimal` 會走專門的 `unwrapDecimal`，對 JSON 數字文字直接呼叫 `Decimal._decimal(from:)`，不經過 Double。[JSONDecoder.swift @ 6669273](https://github.com/swiftlang/swift-foundation/blob/6669273aa38c2306cca8baf92560c92c7b447d1d/Sources/FoundationEssentials/JSON/JSONDecoder.swift#L771-L825)

〔實測〕macOS 26、Swift 6.3.3 的輸出：

```
json 1234.56             -> Decimal 1234.56             | 先解成 Double 再轉 -> 1234.5599999999997952
json 0.30000000000000004 -> Decimal 0.30000000000000004 | 先解成 Double 再轉 -> 0.3000000000000000512
literal `let x: Decimal = 1234.56` -> 1234.5599999999997952
JSONEncoder 編 Decimal(string: "1234.56") -> {"amount":1234.56}
Decimal("1.50") == Decimal("1.5") -> true，而且 hash 相同
```

| 面向 | `Decimal`（建議） | 整數分 `Int` |
|---|---|---|
| 解碼 | 直接從 JSON 文字取得精確值 | 要先解成 `Decimal` 或 `Double` 再乘 100 並捨入，捨入規則寫在 ACL |
| 回寫 API | 編碼成數字文字，可 round-trip | 要除回 100；後端收的是 JS number |
| 後端浮點尾數 | 會原樣保留（例如 `1234.5600000000002`），需要在 ACL 捨入正規化 | 在乘 100 時一併捨入 |
| 顯示 | `Decimal.FormatStyle.Currency` | `IntegerFormatStyle.Currency` 加 `.scale(0.01)` 也行。實測 `123456` 顯示為 `$1,234.56` |
| 陷阱 | 不能用浮點字面值或 `Decimal(Double)` 建值；測試要用 `Decimal(string:)` 或整數字面值 | 忘記換算就差 100 倍。實測沒加 scale 時 `123456` 顯示 `$123,456.00` |
| Apple 範例 | Food Truck 的 `grandTotal: Decimal`（[Order.swift](https://github.com/apple/sample-food-truck/blob/3954a769e99f3cc53297d94f2b960ceb2665b3d6/FoodTruckKit/Sources/Order/Order.swift)） | 未找到 |

〔定義〕Fowler 的 Money 模式也點出捨入問題：「it's easy to lose pennies … because of rounding errors」。[Fowler: Money](https://martinfowler.com/eaaCatalog/money.html)

〔推論〕建議用 `Decimal`。理由是 wire 本來就是十進位文字，JSONDecoder 能直接精確解析，所以不必承擔乘除換算。反過來說，如果金額輸入永遠是整數元，IEEE double 在 2^53 以內能精確表示整數，也就不會出現浮點尾數。所以 iOS 要不要限制只能輸入整數元，也要跟 web 對齊。web 的輸入規則未查證。

〔Apple 文件＋實測〕捨入要對齊 web。Apple 文件寫的是 `rounded(rule: … = .toNearestOrEven, increment:)`。[rounded(rule:increment:)](https://developer.apple.com/documentation/foundation/decimal/formatstyle/currency/rounded(rule:increment:))。ECMA-402 的 `roundingMode` 預設是 `"halfExpand"`，也就是遇到 .5 往遠離 0 的方向進位。[ECMA-402](https://tc39.es/ecma402/#sec-setnfdigitoptions)。本機對照結果：

```
值       iOS 預設   iOS .toNearestOrAwayFromZero   Node 25 Intl.NumberFormat（web 同設定）
0.5      $0         $1                             $1
2.5      $2         $3                             $3
1234.5   $1,234     $1,235                         $1,235
-2.5     -$2        -$3                            -$3
```

我也做了 mutation 測試：把 `.rounded(rule:)` 拿掉，參數化測試的三個 case 全部轉紅。

### 3.3 Entity identity：`Identifiable`

〔Apple 文件〕`Identifiable` 的定義是「A class of types whose instances hold the value of an entity with stable identity」。它的身分範圍可以是「Persistently unique per environment, like database record keys」，而且「It's up to both the conformer and the receiver of the protocol to document the nature of the identity」。[Identifiable](https://developer.apple.com/documentation/swift/identifiable)

`ForEach` 要求元素符合 `Identifiable`，或者另外提供 `id`。[ForEach](https://developer.apple.com/documentation/swiftui/foreach)

〔Apple 文件〕Apple 說明何時用 struct：「Use structures when you're modeling data that contains information about an entity with an identity that you don't control … If the consistency of an app's models is stored on a server, you can model records as structures with identifiers」。它的範例 `PenPalRecord` 把 `myID` 宣告成 `let`，這樣「requests to the database won't accidentally change the wrong record」。[Choosing Between Structures and Classes](https://developer.apple.com/documentation/swift/choosing-between-structures-and-classes)

〔推論〕因此 Entity 的寫法是：`public struct Account: Identifiable, Hashable, Sendable`，`public let id: AccountID`。`AccountID` 是包住 `String` 的 value object，用型別把不同 entity 的 ID 分開。

### 3.4 Swift 6 strict concurrency 對 domain layer 的影響

〔Apple 文件〕`MainActor` 是「A singleton actor whose executor is equivalent to the main dispatch queue」。[MainActor](https://developer.apple.com/documentation/swift/mainactor)。「Classes marked with `@MainActor` are implicitly sendable」。[Sendable](https://developer.apple.com/documentation/swift/sendable)

〔Apple 文件〕WWDC25 的建議：「The Approachable Concurrency setting … We recommend that all projects adopt this setting. For Swift modules that are primarily interacting with the UI, such as your main app module, we also recommend setting the default actor isolation to 'main actor'」。還有「This mode is enabled by default for new app projects created with Xcode 26」。對 library 的建議是「provide a nonisolated API and let clients decide」。[WWDC25 Embracing Swift concurrency](https://developer.apple.com/videos/play/wwdc2025/268/)

〔Apple 文件〕SE-0466 是以 module 為單位設定預設隔離：「Code imported from other modules would be unaffected by the current module's choice of default」。它也說明不把 MainActor 設為全域預設的原因：「`MainActor` isolation is the wrong default for many kinds of modules, including libraries that offer APIs that can be used from any isolation domain」。[SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)

SwiftPM 的對應設定是 `defaultIsolation(_:_:)`，不指定時是 `nonisolated`。[SwiftPM defaultIsolation](https://docs.swift.org/latest/documentation/packagedescription/swiftsetting/defaultisolation(_:_:)/)

〔實測〕把 Domain target 設成 `defaultIsolation(MainActor.self)` 後，乾淨建置時 Infrastructure（nonisolated）裡的 DTO 翻譯程式碼出現一連串錯誤，類型如下：

```
error: call to main actor-isolated initializer 'init(_:)' in a synchronous nonisolated context
error: call to main actor-isolated static method 'isOver(spent:limit:)' in a synchronous nonisolated context
```

改回預設（nonisolated）之後，建置成功。本機 `swift build -v` 也看到 tools-version 6.2 的 package 以 `-swift-version 6` 編譯，Features target 則帶有 `-default-isolation MainActor`。

〔Apple 文件＋推論〕SE-0461 讓 nonisolated async 函式「run on the caller's actor by default」，並引入 `@concurrent` 表示「always switches off of an actor」。[SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)。它由 upcoming feature `NonisolatedNonsendingByDefault` 控制。啟用後，repository 的解碼會在呼叫端（main actor）上執行。以 my-money 的 payload 規模，應該不必特別處理；真的遇到大型列表時，再把翻譯函式標成 `@concurrent`。這點推論未量測。

〔推論〕結論整理如下：

- **Domain**：nonisolated，所有型別都是 `Sendable` 的 value type，不含 actor。
- **Infrastructure**：nonisolated；repository 是 `Sendable` 的 struct。〔Apple 文件〕`URLSession` 與 `JSONDecoder` 都符合 `Sendable`。[URLSession](https://developer.apple.com/documentation/foundation/urlsession)、[JSONDecoder](https://developer.apple.com/documentation/foundation/jsondecoder)
- **Features／App**：設 MainActor 預設。

### 3.5 `@Observable` 放在哪一層

〔Apple 文件〕Observation「provides a robust, type-safe, and performant implementation of the observer design pattern」。[Observation](https://developer.apple.com/documentation/observation)。SwiftUI 只追蹤 `body` 實際讀到的屬性：「If other properties change that body doesn't read, the view is unaffected」。Apple 的範例都把 `@Observable` 套在 class 型的 data model 上。[Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)

改用 Observation 後，可以用 `@State` 和 `@Environment` 取代 `@StateObject` 和 `@EnvironmentObject`。[Migrating to the Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)

〔Apple 文件〕WWDC20 的說法：「Typically, in your app, you store and process data by using a data model that is separate from its UI … you need to manage the life cycle of your data, including persisting and syncing it, handle side-effects … This is when you should use ObservableObject」。[WWDC20 Data Essentials in SwiftUI](https://developer.apple.com/videos/play/wwdc2020/10040/)。Apple 的 Food Truck 範例是 `@MainActor public class FoodTruckModel: ObservableObject`，底下 `@Published` 的是 `Order`、`Donut` 等 struct 陣列。[FoodTruckModel.swift](https://github.com/apple/sample-food-truck/blob/3954a769e99f3cc53297d94f2b960ceb2665b3d6/FoodTruckKit/Sources/Model/FoodTruckModel.swift)

〔實測〕以下兩點可以說明 domain 不該是 `@Observable`：

```
@Observable struct X {}  -> error: '@Observable' cannot be applied to struct type
nonisolated module 裡的 @Observable public final class，傳給 T: Sendable
                         -> error: type 'ObservableAccountProbe' does not conform to the 'Sendable' protocol
```

〔推論〕因此：

- domain 型別維持 immutable 的 `struct`。
- `@Observable` 只放在 Features 層、由 MainActor 隔離的 store 上（Evans 的 application layer 角色：協調 repository、保存畫面狀態）。
- store 持有的是 domain struct 陣列。
- 這個 store 相當於 Fowler 所引用 Evans 說的「kept thin … only coordinates tasks」。

```swift
// MyMoneyFeatures（defaultIsolation(MainActor)）
import Observation
import MyMoneyDomain

@Observable
final class AccountsStore {                     // 模組預設 MainActor，所以隱含 @MainActor
    private(set) var accounts: [Account] = []
    private(set) var failure: String?
    private let repository: any AccountRepository

    init(repository: any AccountRepository) { self.repository = repository }

    func load() async {
        do { accounts = try await repository.accounts() }
        catch { failure = String(describing: error) }
    }
}
```

### 3.6 DTO（`Codable`）與 domain model：分開還是共用

〔定義〕Fowler 說 DTO「whole purpose is to shift data in expensive remote calls」，但也提醒映射成本不低。[Fowler: LocalDTO](https://martinfowler.com/bliki/LocalDTO.html)。〔推論〕iOS 對遠端 API 正是 DTO 的典型用途。代價由一個 module 承擔，換來 domain 型別不帶 wire 怪癖。

〔Apple 文件〕`convertFromSnakeCase` 的轉換規則是：在底線後的字大寫、移除中間的底線；例子 `base_uri` 轉成 `baseUri`，並註明「can't infer capitalization for acronyms or initialisms … define a custom CodingKeys enumeration」。[convertFromSnakeCase](https://developer.apple.com/documentation/foundation/jsondecoder/keydecodingstrategy-swift.enum/convertfromsnakecase)。非預設的 key 策略「may have a noticeable performance cost」。[KeyDecodingStrategy](https://developer.apple.com/documentation/foundation/jsondecoder/keydecodingstrategy-swift.enum)。自訂 key 的做法見 [Encoding and Decoding Custom Types](https://developer.apple.com/documentation/foundation/encoding-and-decoding-custom-types)。

〔實測〕

```
{"account_id":1}，屬性叫 accountID -> DecodingError.keyNotFound: Key 'accountID' not found
{"account_id":1}，屬性叫 accountId -> 1
{"is_active":1}，屬性型別是 Bool  -> DecodingError.typeMismatch: Expected to decode Bool but found number instead.
```

〔推論〕做法如下：

- DTO 的命名照 wire 經過策略轉換後的結果（`accountId`、`isShared: Int`），設為 `internal`，只存在翻譯層。
- 翻譯成 domain 時才改成 Swift 慣例的名稱，例如 `AccountID`、`isShared: Bool`。
- 未知的 enum 字串（例如 `type`）直接丟翻譯錯誤，不要默默套用預設值。

以下程式碼已在本機編譯並通過測試：

```swift
// MyMoneyAPI（翻譯層；DTO 皆為 internal）
struct Envelope<T: Decodable>: Decodable {     // {success, data} / {success:false, error}
    let success: Bool
    let data: T?
    let error: String?
}

struct AccountDTO: Decodable {
    let id: String
    let name: String
    let type: String                            // "bank" | "credit_card"
    let balance: Decimal                        // 直接從 JSON 文字解析，不經 Double
    let unbilled: Decimal
}

enum TranslationError: Error, Equatable { case unknownAccountType(String) }

extension AccountDTO {
    func toDomain() throws -> Account {
        let kind: AccountKind
        switch type {
        case "bank":        kind = .bank(deposit: Money(balance))
        case "credit_card": kind = .creditCard(billed: Money(balance), unbilled: Money(unbilled))
        default:            throw TranslationError.unknownAccountType(type)
        }
        return Account(id: AccountID(id), name: name, kind: kind)
    }
}
```

### 3.7 用 SwiftPM local package 切模組，並用 access control 強制依賴方向

〔Apple 文件〕SwiftPM 文件說：「Each target you define in a Swift package is a module」；module「enforces access controls on which parts of the code can be used outside of that module」；而且「As a rule of thumb: more modules are probably better than fewer modules」。[Introducing Packages](https://docs.swift.org/latest/documentation/packagemanagerdocs/introducingpackages/)

Xcode 文件建議把像「networking logic, source files that contain utilities」這類程式碼搬進 local package，再把 library product 加進 app target 的「Frameworks, Libraries, and Embedded Content」。[Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)

〔Apple 文件〕`package` 存取層級的規格：

- SE-0386：「The `package` access modifier allows symbols to be accessed from outside of their defining module, but only from other modules in the same package」。
- 編譯器判斷是否為同一 package，看的是 `-package-name`；SwiftPM 會自動傳入。
- target 可以設 `packageAccess: false`，讓它「acts as if it's a client outside of the package」，適合「a black-box test target」。

[SE-0386](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0386-package-access-modifier.md)、[packageAccess](https://docs.swift.org/latest/documentation/packagedescription/target/packageaccess/)。TSPL 說明 Xcode 用「Package Access Identifier」build setting 指定 package 名稱。[TSPL: Access Control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/)

〔Apple 文件〕SE-0409 讓 import 可以帶 access level。在 Swift 6 language mode，沒寫的 import 預設仍是 `public`；upcoming feature `InternalImportsByDefault` 會改成 internal。[SE-0409](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md)。〔推論〕Infrastructure 若引入第三方套件（例如 Keychain 包裝），用 `internal import` 可以避免它漏進 public API。

〔實測〕依賴方向的強制力：

```
乾淨建置：Features 沒宣告卻 import Infrastructure -> error: no such module 'Infrastructure'
增量建置（Infrastructure 已先建好）            -> Build complete!（違規沒被抓到）
swift build --explicit-target-dependency-import-check error
  -> error: Target Features imports another target (Infrastructure) in the package without declaring it a dependency.
跨 module 呼叫 internal 函式 -> error: cannot find 'internalOnlyHelper' in scope
跨 module 呼叫 package 函式 -> 通過（同一 package）
```

SwiftPM 對這個旗標的說明是「check whether targets only import their explicitly-declared dependencies」。[swift build](https://docs.swift.org/latest/documentation/packagemanagerdocs/swiftbuild/)

〔實測〕另外兩個實務上的坑：

1. `platforms` 只寫 `.iOS(.v26)` 時，在 Mac 上跑 `swift test` 會失敗：`'Observable()' is only available in macOS 14.0 or newer`。要讓 domain／ACL 測試能在 host 上快速跑，需要加 `.macOS(.v26)`。
2. 本機觀察到 SwiftPM 傳的 `-package-name` 是目錄名（`exp`），而不是 manifest 裡的 `name`。

〔Apple 文件〕WWDC26 介紹了 Swift 6.3 的 module selector（`Module::Type`），用來解決「Swift prefers type names over module names」造成的衝突，但也說「we don't recommend you intentionally design your APIs to have name conflicts」。[WWDC26 What's new in Swift](https://developer.apple.com/videos/play/wwdc2026/262/)。〔推論〕module 名稱不要和型別同名，例如不要取一個叫 `Money` 的 module 又有 `Money` 型別；所以建議用 `MyMoneyDomain` 這類帶前綴的名稱。

### 3.8 Repository protocol 放 Domain、實作放 Infrastructure

〔Apple 文件〕`URLSession.data(for:delegate:)` 是 `async throws -> (Data, URLResponse)`。[data(for:delegate:)](https://developer.apple.com/documentation/foundation/urlsession/data(for:delegate:))。`URLSessionConfiguration.protocolClasses` 可以註冊自訂的 `URLProtocol` 子類來攔截請求，但背景 session 不能用。[protocolClasses](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/protocolclasses)

〔推論〕依賴方向是 Domain 宣告 `protocol AccountRepository: Sendable`，Infrastructure 實作 `public struct LiveAccountRepository`，這就是 Evans 提到的 Hexagonal 形式：domain 不依賴任何基礎設施。另外兩個建議：

- **測試注入點用 `package` 存取層級。** 例如 `package init(fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse))`，讓同一 package 的測試不必 `@testable` 就能注入假的傳輸層，而 package 外的 App 看不到這個 init。
- **錯誤語意照 web 映射。** 在 Domain 定義 `RequestFailure.unauthorized`／`.rejected(message:)` 等錯誤，由 Infrastructure 從 HTTP 狀態碼和 envelope 轉換過來。

### 3.9 測試：Swift Testing 在 domain 與 ACL 層的用法

〔Apple 文件〕Swift Testing「integrates seamlessly with Swift Package Manager testing workflow」，支援參數化、tag、平行執行。[Swift Testing](https://developer.apple.com/documentation/testing)。參數化測試的各個 case「run in parallel with each other」。[Implementing parameterized tests](https://developer.apple.com/documentation/testing/parameterizedtesting)

`#expect` 失敗後測試繼續跑；`#require` 會丟出錯誤並停止測試。[Expectations](https://developer.apple.com/documentation/testing/expectations)。驗證錯誤用 `#expect(throws:)`。[Testing for errors](https://developer.apple.com/documentation/testing/testing-for-errors-in-swift-code)

〔Apple 文件〕Xcode 文件寫到，test function 可以「isolate them to a global actor」；UI 測試「You implement the UI tests for your app using XCTest」；Swift Testing 與 XCTest 可以放在同一個 test bundle。[Adding tests to your Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)。WWDC24 提到 suite「embrace value semantics, encouraging the use of structs to isolate state」。[WWDC24 Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/)

〔推論〕各層的測試方式：

| 層 | 測什麼 | 手法 |
|---|---|---|
| Domain | `Money` 運算與顯示（對齊 web 的捨入）、`YearMonth`／`CalendarDay` 解析、分類清單與 web 常數一致 | 純函式，用 `@Test(arguments:)`。浮點字面值會被 `init(floatLiteral:)` 當成 `Double`，所以測試資料用字串建 `Decimal` |
| ACL（Infrastructure） | 每個 endpoint 真實回應的 fixture JSON，涵蓋成功、`success:false`、401、key 混用、0/1 與 true/false、浮點尾數，解碼加翻譯後得到正確的 domain 值；未知的 enum 字串會丟錯 | 從 repository 的公開 interface 測，注入假傳輸層（interface is the test surface）。本研究的實驗也做了 mutation：把 `credit_card` 的映射對調，測試立刻轉紅 |
| Features store | 載入、錯誤、401 的畫面狀態 | `@MainActor @Test`，搭配 in-memory repository adapter（第二個 adapter，讓 seam 成立）。實驗中的 `loadPublishesAccounts` 已通過 |
| UI | 關鍵流程 | XCTest UI tests |

〔推論〕全域偏好要求「先寫失敗測試要真的跑到紅燈」。ACL 的 fixture 測試特別適合這樣做：先放 fixture、寫 `#expect`，看到紅燈後再寫翻譯。

### 3.10 Apple 官方 sample code 與 WWDC 談了什麼

| 來源 | 實際內容 |
|---|---|
| Backyard Birds（WWDC23） | 拆成 local package `BackyardBirdsData`（manifest 註解「The package that defines the app's data」）和 `BackyardBirdsUI`（「defines the app's user interface elements」）；UI package 依賴 Data package。Data 的資料夾以概念命名：Account、Backyards、Birds、Plants、Store。資料模型是 SwiftData 的 `@Model public class`。[Data Package.swift](https://github.com/apple/sample-backyard-birds/blob/1843d5655bf884b501e2889ad9862ec58978fdbe/BackyardBirdsData/Package.swift)、[UI Package.swift](https://github.com/apple/sample-backyard-birds/blob/1843d5655bf884b501e2889ad9862ec58978fdbe/BackyardBirdsUI/Package.swift)、[sample 文件](https://developer.apple.com/documentation/swiftui/backyard-birds-sample) |
| Food Truck（WWDC22） | 一個 `FoodTruckKit` package，`Sources` 下依概念分資料夾：Account、City、Donut、Order、Store、Truck；`Order` 是 `public struct … Identifiable, Equatable`；model 是 `@MainActor` 的 `ObservableObject`。[FoodTruckKit/Sources](https://github.com/apple/sample-food-truck/tree/3954a769e99f3cc53297d94f2b960ceb2665b3d6/FoodTruckKit/Sources)、[sample 文件](https://developer.apple.com/documentation/swiftui/food-truck-building-a-swiftui-multiplatform-app) |
| WWDC19 Creating Swift Packages | local packages 很適合用來「refactoring out reusable code」，可以把它們想成 workspace 裡的子專案。[WWDC19 410](https://developer.apple.com/videos/play/wwdc2019/410/) |
| WWDC20 Data Essentials in SwiftUI | data model「separate from its UI」；source of truth 是資料模型設計中最重要的問題。[WWDC20 10040](https://developer.apple.com/videos/play/wwdc2020/10040/) |
| WWDC25 Embracing Swift concurrency | 以 module 為單位設定隔離：UI module 預設 main actor，library 提供 nonisolated API。[WWDC25 268](https://developer.apple.com/videos/play/wwdc2025/268/) |
| WWDC26 SwiftUI Group Lab | 「there's really no architecture that we expect you to adopt. SwiftUI is really designed to be architecture agnostic」。在 multi-module app 中，想隱藏具體的 view 型別時，能用 `some View` 就用，用不了才用 `AnyView`。[WWDC26 8006](https://developer.apple.com/videos/play/wwdc2026/8006/) |
| WWDC24 Migrate your app to Swift 6 | 以 CoffeeTracker 示範 Swift 6 的逐步遷移。Apple 文件另寫「If your app is organized into multiple modules, you can migrate your code one module at a time」。[WWDC24 10169](https://developer.apple.com/videos/play/wwdc2024/10169/)、[Adopting strict concurrency](https://developer.apple.com/documentation/swift/adoptingswift6) |
| 沒找到的 | 本次查閱的文件和 session 裡，沒有任何一篇規定 Domain／Infrastructure／Features 分層，或提到 DDD、Clean Architecture。WWDC23 Meet mergeable libraries 談的是連結方式與建置速度，不是分層。**只是這次沒找到，不代表不存在**。 |

## 4. 給 my-money.ios 的具體建議（本節全部為推論）

### 4.1 模組樹

```
my-money.ios/
├── CONTEXT.md                      ← UL 詞彙表（沿用後端和 web 的用語）
├── docs/adr/
├── MyMoney.xcodeproj
├── App/                            ← Xcode app target：composition root
│   └── MyMoneyApp.swift            （@main、組裝 Live*Repository、注入根畫面）
├── Packages/MyMoneyKit/            ← 單一 local package、多個 target
│   ├── Package.swift
│   ├── Sources/
│   │   ├── MyMoneyDomain/          ← 無依賴、nonisolated、只 import Foundation
│   │   │   ├── Shared/             Money、YearMonth、CalendarDay、ViewScope、RequestFailure
│   │   │   ├── Accounts/           Account、AccountID、AccountKind、BalanceSummary、AccountRepository
│   │   │   ├── Transactions/       Transaction、TransactionKind、Category、CategorySummary、TransactionRepository
│   │   │   ├── Recurring/          RecurringItem、BillingCycle、Amortization、RecurringRepository
│   │   │   ├── Goals/              Goal、GoalRepository（deposit）
│   │   │   ├── Budgets/            Budget、BudgetStatus（spent／over 由伺服器算）、BudgetRepository
│   │   │   ├── Forecast/           CashFlowForecast、PurchaseCheck、SpendingVerdict、CashFlowForecasting
│   │   │   ├── Household/          Household、HouseholdMember、Invitation、HouseholdRepository
│   │   │   └── Auth/ ・ Bot/        （generic subdomain，保持最薄）
│   │   ├── MyMoneyAPI/             ← 翻譯層（ACL）：只依賴 MyMoneyDomain
│   │   │   ├── Transport/          HTTP、Envelope、錯誤映射（對齊 web client.ts）、token 儲存
│   │   │   ├── DTO/                internal：wire 形狀
│   │   │   └── Repositories/       public Live*Repository（URLSession）
│   │   ├── MyMoneyFeatures/        ← SwiftUI View＋@Observable store；defaultIsolation(MainActor)
│   │   │   └── Accounts/ Transactions/ Budgets/ Forecast/ Goals/ Recurring/ Household/ Auth/ Bot/
│   │   └── MyMoneyTestSupport/     ← in-memory adapter 與 fixture 載入（只給測試用）
│   └── Tests/
│       ├── MyMoneyDomainTests/
│       ├── MyMoneyAPITests/        ← Fixtures/：每個 endpoint 的真實回應
│       └── MyMoneyFeaturesTests/
└── MyMoneyUITests/                 ← XCTest UI tests
```

### 4.2 依賴方向與強制方式

```
App ──▶ MyMoneyFeatures ──▶ MyMoneyDomain ◀── MyMoneyAPI ◀── App
Tests：FeaturesTests ──▶ Features ＋ TestSupport ──▶ Domain
```

- **Features 不依賴 API。** 由 App 組裝 Live repository 並注入。這樣 View 和 store 不可能碰到 DTO。
- **強制手段有三層：**
  1. `Package.swift` 的 target dependencies。
  2. CI 跑 `swift build --explicit-target-dependency-import-check error` 和 `swift test`，因為第 3.7 節實測顯示增量建置會放過違規。
  3. access control：DTO 設 `internal`，只給同 package 用的測試注入點設 `package`，App 需要的東西才設 `public`。
- **public 面積越小越好**（deep module）：Features 只公開根 View 和一個依賴容器；MyMoneyAPI 只公開 `Live*Repository` 的 init。
- **先用一個 Features target 就夠。** 等建置時間或協作需求出現，再依 Evans 的 Modules 原則按概念拆開。這符合 Fowler 說的「once any of these layers gets too big you should split your top level into domain oriented modules which are internally layered」。[Fowler: PresentationDomainDataLayering](https://martinfowler.com/bliki/PresentationDomainDataLayering.html)

### 4.3 各層放什麼

| 層 | 放 | 不放 |
|---|---|---|
| MyMoneyDomain | value object、struct entity、repository 與 domain service 的 protocol、從 web 搬過來的前端規則（分類清單、週期標籤、金額顯示規則、預設日期規則） | SwiftUI、URLSession、Codable DTO、`@Observable`、任何伺服器規則的重算 |
| MyMoneyAPI | DTO、`Envelope<T>`、key 與 0/1 翻譯、`balance` 拆義、Decimal 正規化、錯誤映射、token 儲存 | 畫面狀態、商業判斷 |
| MyMoneyFeatures | View、`@MainActor @Observable` store（協調 repository、保存 loading／error 狀態） | 直接解析 JSON、`if type == "credit_card"` 這類判斷 |
| App | 組裝與導覽根節點 | 其他任何邏輯 |

不需要 SwiftData 或本地持久化。本次查看的 web 程式碼裡，localStorage 只存 token、使用者資訊和主題偏好，沒有資料快取（[client.ts L4–6](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/api/client.ts#L4-L6)、[useStore.ts L37–96](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/store/useStore.ts#L37-L96)）。加入離線功能就違反「不增加」。token 在 iOS 改存 Keychain，屬於 Infrastructure 的事，不改變功能。

### 4.4 刻意不用的 DDD 構件

| 構件 | 不用的理由 |
|---|---|
| Aggregate root 實作（含不變條件的方法） | 一致性與交易邊界都在伺服器，client 端寫一份等於重算規則，違反對等；只保留「用 ID 參照」的紀律 |
| Domain Event | 後端沒有事件流；新增或修改後重抓屬於 system event，用 store 重新載入即可。Evans 明確把 domain event 和 system event 分開 |
| 獨立 Factory 物件 | 建立由伺服器負責，還原由翻譯層的 `toDomain()` 處理，不符合 Evans「creation … becomes complicated」的觸發條件 |
| 本地 Domain Service 實作（預測、消費檢查、餘額、超支） | 規則屬於伺服器；iOS 只保留 protocol，實作是遠端呼叫 |
| 每個操作一個 UseCase class | 如果它只是轉呼叫 repository，就是 pass-through，過不了 deletion test；store 已經扮演 Evans 所說「thin」的 application layer |
| 完整 ACL 或自有模型 | 見 1.4 節：iOS 沒有需要保護的獨立模型，另建一套只會與 web 分岔 |
| Shared Kernel 或 codegen 共用型別 | 後端凍結、語言不同；fixture 加 CONTEXT.md 就夠當事實上的 Published Language |

### 4.5 `CONTEXT.md` 與 ADR 的起手清單

建議先寫進 `CONTEXT.md` 的詞條。概念來自原始碼；中文名稱要以 web 畫面上的用語為準，**未逐頁查證**：

- 帳戶：分銀行帳戶（bank）與信用卡（credit_card）。
- 存款餘額（bank 的 `balance`）、已出帳金額（credit_card 的 `balance`）、未出帳金額（`unbilled`）。
- 可用餘額（`available`）與可支配金額（`disposable`），兩者都由伺服器計算。
- 交易的收入／支出、分類、共同支出（`is_shared`）。
- 檢視範圍（`all`／`household`／`personal`）。
- 固定收支與攤提。
- 目標、存入、每月預留。
- 預算、已花費、超支（伺服器判定）。
- 現金流預測、最低餘額、會透支。
- 消費檢查與判定（`safe`／`caution`／`danger`）。
- 家庭、成員、邀請碼。
- Bot 綁定。

ADR 候選。挑選標準沿用 trip-planner 的三條件：難以逆轉、沒有 context 會讓人困惑、確實有取捨。

1. **context 關係**：語意 Conformist 加薄翻譯層，並寫明不採完整 ACL 的原因。
2. **金額**：用 `Decimal`、單一幣別 TWD、正規化與顯示捨入的規則（對齊 web 的 halfExpand）。
3. **模組切法與依賴方向**：包含 CI 的 import 檢查。
4. **隔離預設**：Domain 與 API 為 nonisolated，Features 與 App 為 MainActor。

### 4.6 要在 grill 階段決定的事

- **`today()`／`thisMonth()` 的時區。** web 用 UTC，台灣在凌晨 0 點到 8 點之間預設日期會是前一天。「完全對等」是否包含重現這個行為？這是產品決策。[utils.ts L17–23](https://github.com/onion523/my-money/blob/43a205d4366337fbec9d672cfc49e27b4f2cf48c/web/src/components/utils.ts#L17-L23)
- **金額輸入是否限制為整數元。** 這決定後端浮點尾數會不會出現，以及 ACL 要不要捨入。web 表單的輸入規則未查證。
- **新增或修改後重抓哪些資料。** 例如新增交易後，是否重抓餘額、預算、預測。要對照 web 各頁面的實際行為，未查證。
- **ACL 的捨入規則。** 是只在顯示時捨入，還是解碼時就正規化到固定位數。

## 未查證與不確定的項目

- **Vernon 的 *Implementing Domain-Driven Design* 書中內容（包括 context mapping 章節）未查證**，只引用了他 2011 年的 dddcommunity.org 文章。Evans 對 application layer 的描述是轉引自 Fowler 的 AnemicDomainModel 條目，原書頁碼未查證。
- **iOS 執行環境未實測。** Decimal 解碼、FormatStyle 捨入、Observation 的行為都只在 macOS 26 host 驗證過。swift-foundation 引用的是 main 分支的原始碼；iOS 26 內建的 Foundation 是否逐行相同，未驗證。
- **Xcode 建置系統未實測。** 「沒宣告的 import 在增量建置時能通過」只在 SwiftPM CLI 觀察到。Xcode 建置 app 時的 implicit dependency 行為，以及 App target 能否透過 Package Access Identifier 加入 local package 的 `package` 邊界，都沒有實測。
- **SwiftPM 的 package identity。** `-package-name` 取目錄名只是本機觀察，沒有找到文件明文說明。
- **後端浮點尾數**是從原始碼（JS `reduce`、SQL `SUM`、REAL）推論而來，沒有在實際 API 回應中觀察到。ECMAScript 數字序列化的細節也沒有逐條核對規格。
- **web 的 UTC 日期行為和分類常數**是讀原始碼得到的，沒有實際執行 web。web 各頁面的重抓行為與表單驗證規則未查證。
- **Node 25 的 `Intl` 結果**被拿來代表瀏覽器行為，依據是 ECMA-402 規格的預設值。Safari 和 Chrome 沒有個別驗證。
- **WWDC 的搜尋範圍有限。** 只看了表中列出的 session 逐字稿，所以「Apple 沒有規定分層」是指這次查閱的範圍。
- **SE-0461 的效能影響。** 啟用 `NonisolatedNonsendingByDefault` 後，解碼改在 main actor 上執行，對效能的影響沒有量測。Xcode 的「Approachable Concurrency」到底包含哪些 upcoming feature，沒有逐一核對。
