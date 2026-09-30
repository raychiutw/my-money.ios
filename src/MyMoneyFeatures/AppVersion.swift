import Foundation
import SwiftUI

/// app 的版號與 build 號，顯示在「我的」的設定底部(DESIGN.md「導覽」)。
public struct AppVersion: Equatable, Sendable {
    /// `CFBundleShortVersionString`,例如 `0.1.0`。
    public let shortVersion: String
    /// `CFBundleVersion`。TestFlight 上是 workflow run ID,本機建置是專案預設值 `1`。
    public let build: String

    /// 前後的空白不算。
    public init(shortVersion: String, build: String) {
        self.shortVersion = shortVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.build = build.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 從 Info.plist 的內容組出來，composition root 傳入 `Bundle.main.infoDictionary`。
    public init(infoDictionary: [String: Any]?) {
        self.init(
            shortVersion: infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build: infoDictionary?["CFBundleVersion"] as? String ?? ""
        )
    }

    /// 例如「版本 0.1.0（36707214745）」。沒有 build 號就不顯示括號;讀不到版號寫「未知」。
    public var text: String {
        let version = shortVersion.isEmpty ? "未知" : shortVersion
        return build.isEmpty ? "版本 \(version)" : "版本 \(version)（\(build)）"
    }
}

extension EnvironmentValues {
    /// 由 composition root 注入;測試可以放固定的值。
    @Entry public var appVersion = AppVersion(shortVersion: "", build: "")
}
