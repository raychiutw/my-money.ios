import Foundation

/// 畫面 model 的載入階段(#210 第 1 項)。各 model 以 `typealias Phase = LoadPhase` 沿用,畫面與測試的寫法不變。
public enum LoadPhase: Equatable {
    /// 第一次載入，還沒有任何資料:畫面只顯示載入中，不顯示 `$0`。
    case loading
    case loaded
    case failed(String)

    /// 載入失敗:訊息取自錯誤的 `localizedDescription`。
    public static func failure(_ error: Error) -> LoadPhase {
        .failed(error.localizedDescription)
    }
}

/// 沒有檢視範圍的畫面用。
public struct Unscoped: Hashable, Sendable {
    public init() {}
}

/// 「什麼變了要重新載入」的鍵(#211 第 1 項):檢視範圍(統計頁還有月份)加資料版本。
/// model 的 `reloadKey` 是唯一定義;畫面用它當 `.task(id:)`,`refreshIfStale` 也跟它比對。
public struct ReloadKey<Scope: Hashable & Sendable>: Hashable, Sendable {
    public let scope: Scope
    public let version: Int

    public init(scope: Scope, version: Int) {
        self.scope = scope
        self.version = version
    }
}

extension ReloadKey where Scope == Unscoped {
    public init(version: Int) {
        self.init(scope: Unscoped(), version: version)
    }
}

/// 上一次載入成功時的重載鍵;跟目前的鍵不同就是過期(#210 第 1 項)。
public struct LoadFreshness<Scope: Hashable & Sendable> {
    public private(set) var key: ReloadKey<Scope>?

    public init() {}

    public var version: Int? { key?.version }
    public var scope: Scope? { key?.scope }

    public func isStale(_ current: ReloadKey<Scope>) -> Bool {
        key != current
    }

    public mutating func markLoaded(_ loaded: ReloadKey<Scope>) {
        key = loaded
    }
}
