import Foundation

/// 表單 model 的送出(#210 第 2 項):送出中旗標與失敗訊息的規則只在這裡。
///
/// 送出前的檢查(缺欄位、金額不對)各 model 自己做,直接寫 `errorMessage`;通過之後的實際送出交給 `submitting`。
@MainActor
package protocol Submitting: AnyObject {
    var isSaving: Bool { get set }
    var errorMessage: String? { get set }
}

extension Submitting {
    /// 執行一次送出:期間 `isSaving` 為 true(畫面據此停用送出鈕)。
    /// 成功回傳 `work` 的結果;失敗把錯誤訊息放進 `errorMessage`(錯誤沒有訊息時用 `fallback`)並回傳 `nil`。
    package func submitting<T>(failure fallback: String, _ work: () async throws -> T) async -> T? {
        isSaving = true
        defer { isSaving = false }
        do {
            return try await work()
        } catch {
            let message = error.localizedDescription
            errorMessage = message.isEmpty ? fallback : message
            return nil
        }
    }
}
