import Foundation

/// 列表上的變更(#211 第 2 項):刪除、結帳日出帳等不在表單裡的操作。
/// 成功才遞增資料版本(其他畫面重抓);失敗只設 `alertMessage`,畫面用 `errorAlert` 顯示。
@MainActor
package protocol Alerting: AnyObject {
    var alertMessage: String? { get set }
}

extension Alerting {
    /// 執行一次變更:成功遞增資料版本並回傳結果;失敗設 `alertMessage`、回傳 `nil`、不遞增。
    package func commit<T>(_ dataVersion: DataVersion, _ work: () async throws -> T) async -> T? {
        do {
            let result = try await work()
            dataVersion.bump()
            return result
        } catch {
            alertMessage = error.localizedDescription
            return nil
        }
    }
}
