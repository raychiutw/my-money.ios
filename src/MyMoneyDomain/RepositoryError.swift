import Foundation

/// repository 失敗的原因，由翻譯層從 HTTP 狀態碼與 envelope 映射而來。
public enum RepositoryError: Error, Equatable, Sendable {
    /// 後端拒絕請求，並附上給人看的訊息(`{success: false, error}`),原樣顯示。
    case rejected(String)

    /// 回應不是看得懂的 envelope,例如後端出錯時回的純文字。
    case unreadableResponse

    /// token 無效或已過期(非 `/auth/*` 的請求回應 401)。app 會清掉 session、回到登入頁。
    case sessionExpired
}

extension RepositoryError: LocalizedError {
    /// 顯示給使用者的訊息，跟 web 一致。
    public var errorDescription: String? {
        switch self {
        case .rejected(let message):
            message
        case .unreadableResponse:
            "伺服器無回應"
        case .sessionExpired:
            // 不會顯示:app 直接回到登入頁。
            nil
        }
    }
}
