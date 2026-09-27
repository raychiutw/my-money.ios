---
status: accepted
---

# 畫面層用 Apple SwiftUI 資料流，不用 TCA

畫面層採 Apple 自家的資料流:每個畫面一個 `@MainActor @Observable` 畫面 model,相當於 MVVM 的 ViewModel。畫面 model 由父層或路由建立後傳入，不在 view 裡用 `@State` 直接建立。app 層級的共享物件用 `Environment` 往下傳，其餘一律 initializer 注入，`App` 是唯一的 composition root。不用 TCA,也不引入第三方 DI 容器。

TCA 是最受歡迎的第三方 SwiftUI 架構(2026-09-28 查詢時 14,937★)。它的官方 FAQ 說，在「主要從網路載入 JSON 再顯示」的 reader app 上,TCA 不太能發揮，因為這類 app「don't tend to have much in the way of nuanced logic or complex side effects」;FAQ 也建議可以先用 vanilla SwiftUI,真的需要時再轉([FAQ](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Sources/ComposableArchitecture/Documentation.docc/Articles/FAQ.md))。

my-money 不是純 reader app:它有 CRUD 表單、本機篩選、分頁、跨畫面刷新(記一筆之後，總覽、帳戶、統計都要更新)、配對碼倒數。但依 ADR-0001,業務規則都在後端，副作用只有「呼叫 API,再重新整理」這一種。TCA 最主要的優勢在複雜 state 的組合，以及 effect 的編排與窮盡測試，本 app 幾乎用不到。它的成本卻一樣不少：帶進 12 個 package 加上 swift-syntax、學習曲線，而且違反「第一方優先」的套件政策。另外,TCA 的 reducer 會讓 client 端多出第二套規則模型，跟 Conformist 衝突。

用 Apple 資料流時，那兩項 TCA 做得比較好的事，改用下面的方式處理：
- **跨畫面刷新**:由一個 app 層級的 `@Observable` 物件持有資料版本，資料被修改後遞增版本，各畫面 model 看到版本改變就重新抓資料。
- **行為測試**:畫面 model 注入 in-memory repository,用 Swift Testing 驗證 state 的變化。

## Considered Options

- **TCA**:理由如上。
- **完整的 Clean Architecture 或 VIPER**:每個操作一個 UseCase class,但這些 class 只是把呼叫轉給 repository,通不過 deletion test;VIPER 的命令式 Router 也和 SwiftUI 資料驅動的導覽互相衝突。本專案只採用 Clean Architecture 的「分層 + 依賴反轉」:SwiftPM target 分成 Domain、API、Features,Features 不 import API。
- **Factory 或 swift-dependencies 這類 DI 容器**:一個 app target、四個模組的規模，建構子注入就夠用。真的需要容器時，備案是 Factory(零 runtime 依賴，維護活躍)。

## 何時重新評估

出現下列任一情況時，重新評估是否改用 TCA:
- 需要離線同步，或 client 端必須協調多個互相依賴的非同步流程。
- 出現多步驟、有分支的表單流程(例如精靈式的設定)。
- 跨畫面同步的狀態超出「資料版本遞增 → 重新抓取」能處理的範圍。

TCA 1.25 起陸續 deprecate API,為 2.0 鋪路([1.25.0 release](https://github.com/pointfreeco/swift-composable-architecture/releases/tag/1.25.0))。重新評估時，要以當時 2.0 的狀態為準。

調查依據見 `docs/research/2026-09-28-ios-app-architecture-frameworks.md` 與 `docs/research/2026-09-28-ddd-ios-swiftui.md`。
