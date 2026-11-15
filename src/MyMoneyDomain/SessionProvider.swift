/// app 這一側的 session,給翻譯層使用:取得目前的 token,以及在後端判定 session 失效時通知 app。
///
/// 翻譯層只透過這個 protocol 認識 session,所以 API 不必依賴 Features。
public protocol SessionProvider: Sendable {
    /// 目前登入中的 JWT;未登入時是 `nil`。
    func currentToken() async -> String?

    /// 請求回應 401 且 `WWW-Authenticate` 含 `invalid_token` 時呼叫:app 要清掉 session、回到登入頁。
    func sessionDidExpire() async
}
