---
status: accepted
---

# 畫面層用 Apple SwiftUI 資料流，不用 TCA

畫面層採 Apple 自家的資料流:每個畫面一個 `@MainActor @Observable` 畫面 model,相當於 MVVM 的 ViewModel。畫面 model 由父層或路由建立後傳入，不在 view 裡用 `@State` 直接建立。app 層級的共享物件用 `Environment` 往下傳，其餘一律 initializer 注入，`App` 是唯一的 composition root。不用 TCA,也不引入第三方 DI 容器。

TCA 是最受歡迎的第三方 SwiftUI 架構(2026-09-28 查詢時 14,937★),但它的官方 FAQ 明說不太適合「主要從網路載入 JSON 再顯示」的 app,也建議可以先用 vanilla SwiftUI、真的需要時再轉([FAQ](https://github.com/pointfreeco/swift-composable-architecture/blob/1.26.2/Sources/ComposableArchitecture/Documentation.docc/Articles/FAQ.md))。依 ADR-0001,本 app 的規則都在後端，正好是這種型態。TCA 的 reducer 會在 client 端形成第二套規則模型，跟 Conformist 衝突。它也會帶進 12 個 package 加上 swift-syntax,違反「第一方優先」的套件政策。

## Considered Options

- **TCA**:理由如上。
- **完整的 Clean Architecture 或 VIPER**:每個操作一個 UseCase class,但這些 class 只是把呼叫轉給 repository,通不過 deletion test;VIPER 的命令式 Router 也和 SwiftUI 資料驅動的導覽互相衝突。本專案只採用 Clean Architecture 的「分層 + 依賴反轉」:SwiftPM target 分成 Domain、API、Features,Features 不 import API。
- **Factory 或 swift-dependencies 這類 DI 容器**:一個 app target、四個模組的規模，建構子注入就夠用。真的需要容器時，備案是 Factory(零 runtime 依賴，維護活躍)。

調查依據見 `docs/research/2026-09-28-ios-app-architecture-frameworks.md` 與 `docs/research/2026-09-28-ddd-ios-swiftui.md`。
