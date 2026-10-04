# CLAUDE.md

這份文件提供 Claude Code 在此 repository 工作時的指引。

## 專案性質

[my-money](https://github.com/onion523/my-money) web 版「我的記帳本」的 iOS 原生 client(SwiftUI)。**後端凍結、不歸我們管**:iOS 共用同一套 Cloudflare Workers API(`https://my-money-api.onion523.workers.dev`),只當另一個 client。多數設計決策都由這個限制推導而來，詳見 ADR-0001。

- **功能層與 web 對等，互動層照 HIG 轉譯，照抄程式流程,bug 不照抄。** web 沒有的功能不加;純前端 bug 用現有 API 修正;每一處跟 web 不同的地方都要列進 `docs/parity.md`。
- 規格：最低 iOS 26.0,用 Xcode 27(iOS 27 SDK)建置,Universal(iPhone + iPad),bundle id `com.raychiu.mymoney`,只透過 TestFlight 內部測試發佈，不上 App Store,原因見 ADR-0001 的後果一節。

## 常用指令

```bash
swift test --explicit-target-dependency-import-check error     # package 全部測試，並檢查依賴方向
swift test --filter MyMoneyAPITests                             # 單一 test target
xcodebuild test -project src/App/MyMoney.xcodeproj -scheme MyMoney \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath .derivedData -parallel-testing-enabled NO \
  -only-testing:MyMoneyUITests/TransactionsUITests              # UI 測試:本機跑，只跑有修改到的類別(CI 不做);不加 -only-testing 是全部(不平行，避免複製模擬器)
xcodebuild build -scheme MyMoney-Package -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData/package SWIFT_TREAT_WARNINGS_AS_ERRORS=YES  # 以 iOS 編譯 package
scripts/record-fixture.sh <檔名> <METHOD> <path> [body]         # 從 prod 錄 fixture,見 Fixtures/README.md
scripts/screen-tour.sh [-o 輸出目錄] [-a light,dark] [-s default,xxl,ax5]  # 截圖巡覽，預設輸出到 /tmp/my-money-screen-tour,見 DESIGN.md「截圖巡覽」
gh workflow run testflight.yml --ref master                     # 手動重發 TestFlight(合併進 master 會自動上傳);每次發佈都要先遞增 MARKETING_VERSION,見 docs/testflight.md
```

warning 當 error 有三道：`Package.swift` 的 `treatAllWarnings`(只對 macOS,也就是 `swift test`)、app 專案的 `SWIFT_TREAT_WARNINGS_AS_ERRORS`,以及上面第四行的 package iOS 編譯。Xcode 建置 app 時會把 package 的 warning 壓掉，所以第四行不能省。

開發時直接連 prod API,**一律用專用測試帳號**(`mymoney-ios-test@example.com`),而且這個帳號不加入任何家庭。密碼不進 repo:存在本機 Keychain(service `my-money-ios-test`),或放在環境變數 `MYMONEY_TEST_PASSWORD`。

## 開發流程(強制)

- **一律走 Matt Pocock skill 工作流**:`/grill-with-docs` → `/to-spec` → `/to-tickets` → `/implement`。單一 session 做得完的小功能，grill 完可以直接 `/implement`。忘記該用哪個 skill 就問 `/ask-matt`。
- **TDD 紅綠重構**:任何 production code 變更都先寫失敗測試，而且要**真的跑出紅燈並留下輸出**。修 bug 先寫重現測試。
- **完成定義**:`swift test` 和 `xcodebuild test` 全部通過，而且零 warning(`-warnings-as-errors`)。**CI 不做 UI 測試**(太久);UI 測試在本機跑，**只跑有修改到的**(用 `-only-testing:MyMoneyUITests/類別名`),不必每次跑全部。CI 只編譯 app、跑 package 測試。
- **不直接 commit 到 `master`**:開 feature branch,push 後開 PR,合併時用 **merge commit**,不用 squash。
- 文件、註解、commit message 一律用繁體中文(台灣用語),技術名詞保留英文。
- 詞彙在 `CONTEXT.md`,UI 規範在 `DESIGN.md`,功能對等清單在 `docs/parity.md`,難以逆轉的決策在 `docs/adr/`,一手來源研究在 `docs/research/`。

## 架構

DDD 分層，由 SwiftPM target 強制依賴方向(ADR-0001、ADR-0002)。頂層固定是 `src/` 和 `tests/`:

```text
Package.swift                  # 根目錄 local package,用 path: 指向 src/、tests/
src/App/MyMoney.xcodeproj      # app target、UI test target(buildable folders)
src/App/MyMoney/               # @main、composition root:組裝 live 依賴
src/MyMoneyDomain/             # 值物件、Entity、Repository protocol;不依賴任何 target
src/MyMoneyAPI/                # 翻譯 seam:DTO、envelope、URLSession 實作 repository
src/MyMoneyFeatures/           # SwiftUI 畫面 + 每畫面一個 @MainActor @Observable model
tests/MyMoneyTestSupport/      # in-memory repository、fixtures
tests/MyMoney{Domain,API,Features}Tests/
tests/MyMoneyUITests/          # XCUITest
```

依賴方向:`App → Features → Domain ← API ← App`。**Features 不 import API**,所以 View 碰不到 DTO。`Package.swift` 的 `platforms` 要包含 `.macOS(.v26)`,否則在 Mac 上跑 `swift test` 時,Observation 會編譯失敗。

### 規則

- **不在 client 端重算業務規則**。淨可用餘額、預測、購買力試算、超支判斷都用後端回傳的值。後端的錯我們也照舊顯示，只有 `docs/parity.md` 列出的偏離例外。
- **wire format 只在 `MyMoneyAPI` 裡處理**,不設全域 `keyDecodingStrategy`。資料表欄位是 snake_case,計算型 endpoint(`/accounts/balance`、`/forecast`)是 camelCase,而且 camelCase 物件裡還包著 snake_case;資料庫旗標是 0/1(`is_shared`),計算出來的旗標是 true/false(`over`、`willOverdraft`)。回應 envelope 是 `{success, data}` 或 `{success:false, error}`,部分 DELETE 只回 `{success, message}`,沒有 `data`。
- **「信用卡還款」是系統分類**:信用卡扣款還款(`POST /accounts/pay-credit-card`)產生的交易記錄，活存帳戶一筆支出、信用卡一筆收入。後端禁止編輯和刪除(回 400),統計也都排除它;iOS 的列表不顯示編輯和刪除，交易頁本機算的總收入和總支出也都排除它。
- **`balance` 一詞兩義**:活存帳戶的 `balance` 是「餘額」,信用卡的 `balance` 是「已出帳待繳款」。翻譯層要把它拆成兩個不同的 domain 概念。
- **金額用 `Decimal`**。顯示新台幣時設 0 位小數，並加上 `.rounded(rule: .toNearestOrAwayFromZero)`,才會跟 web 的 `Intl` 一樣(2.5 → `$3`)。
- **日期**:「今天」和「本月」一律用台灣時間算。呼叫 API 時明確帶上月份，不依賴後端用 UTC 算的預設值。wire 上的日期維持 `YYYY-MM-DD` 字串。
- **DI**:只用 initializer 注入;app 層級的物件用 `Environment` 往下傳;`App` 是唯一的 composition root。畫面 model 由父層或路由建立後傳入，不在 view 裡用 `@State` 直接建立。
- **Concurrency**:Domain 型別是 `Sendable` 的 value type;API 層維持 nonisolated;畫面 model 放在 main actor。
- **認證**:JWT 存在 Keychain(Security framework),效期 30 天，沒有 refresh。任何非 `/auth/*` 的 401 都清掉 token、回到登入頁。這件事只在 `APIClient` 一個地方判斷：它透過 Domain 的 `SessionProvider` 通知 `AppSession`,所以新的 repository 只要經過 `APIClient` 就自動套用，畫面 model 不必自己處理。
- **套件政策**:優先用 Apple 第一方。第一方真的做不到時，才用最活躍的免費第三方套件，並在 PR 說明第一方為什麼做不到。

## 測試慣例

- 單元測試和 integration 測試用 Swift Testing;少數 UI 流程用 XCTest/XCUITest。兩者分開 target。
- `MyMoneyAPITests` 的 fixture 是用測試帳號從 prod 錄下來的**真實回應**(`tests/MyMoneyAPITests/Fixtures/`),不照程式碼手寫，用 `scripts/record-fixture.sh` 錄(token 會換成假值)。流程和清單見 `tests/MyMoneyAPITests/Fixtures/README.md`。網路用 `URLProtocol` stub(`HTTPStub`,每個測試一個 host,可以平行跑)。
- UI 測試不連網路：啟動參數帶 `-uiTesting` 時，由 composition root 換成 `MyMoneyTestSupport` 的 in-memory repository(登入帳密是 `InMemoryAuthRepository.Member.sample`)。session 仍存在模擬器的 Keychain(UI 測試專用的 service),再加 `-resetSession` 會在啟動時清掉。唯一的例外是 `BrandColorUITests`:它不帶 `-uiTesting`,驗證 TestFlight 走的正式路徑，只停在登入頁(不連網路);模擬器裡有正式 session 時會 skip。
- 畫面 model 測試要觀察「送出期間」的狀態時，用 `MyMoneyTestSupport` 的 `Gate` 讓 in-memory repository 停住，不用 `sleep`。
- 測試名稱使用 `CONTEXT.md` 的詞彙。

## Agent skills

### Issue tracker

Issues 和 PRD 用 GitHub Issues(`raychiutw/my-money.ios`),透過 `gh` CLI 操作。詳見 `docs/agents/issue-tracker.md`。上游 web 或後端的問題，一律回報到 `onion523/my-money`。

### Triage labels

使用預設的五種 triage label:`needs-triage`、`needs-info`、`ready-for-agent`、`ready-for-human`、`wontfix`。詳見 `docs/agents/triage-labels.md`。

### Domain docs

採 single-context。根目錄的 `CONTEXT.md` 是**詞彙表**;web 日後若建立自己的 `CONTEXT.md`,以它為 source of truth。詳見 `docs/agents/domain.md`。
