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
public struct Unscoped: Equatable, Sendable {
    public init() {}
}

/// 「資料版本或檢視範圍在上一次載入之後改變過，才重新載入」的判斷(#210 第 1 項)。
/// 載入成功時呼叫 `markLoaded`;`refreshIfStale` 先問 `isStale` 再決定要不要載入。
public struct LoadFreshness<Scope: Equatable> {
    public private(set) var version: Int?
    public private(set) var scope: Scope?

    public init() {}

    public func isStale(version current: Int, scope currentScope: Scope) -> Bool {
        version != current || scope != currentScope
    }

    public mutating func markLoaded(version loaded: Int, scope loadedScope: Scope) {
        version = loaded
        scope = loadedScope
    }
}

extension LoadFreshness where Scope == Unscoped {
    public func isStale(version current: Int) -> Bool {
        isStale(version: current, scope: Unscoped())
    }

    public mutating func markLoaded(version loaded: Int) {
        markLoaded(version: loaded, scope: Unscoped())
    }
}
