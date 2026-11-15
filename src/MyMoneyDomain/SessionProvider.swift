/// app 這一側的 session,給翻譯層使用:取得目前的權杖、保存 refresh 換到的新權杖,以及在登入工作階段失效時通知 app。
///
/// 翻譯層只透過這個 protocol 認識 session,所以 API 不必依賴 Features。
public protocol SessionProvider: Sendable {
    /// 目前登入工作階段的權杖;未登入時是 `nil`。冷啟動時只有更新權杖(存取權杖是 `nil`),翻譯層會先 refresh。
    func currentTokens() async -> SessionTokens?

    /// refresh 成功(更新權杖已輪替):換成新的權杖並存到裝置上(#335)。
    /// `previousRefresh` 是這次 refresh 送出的更新權杖;目前的 session 已經不是它(登出後又登入)時不理會。
    func sessionDidRefresh(_ tokens: SessionTokens, replacing previousRefresh: String) async

    /// 登入工作階段失效時呼叫(refresh 回 `invalid_grant`,或 refresh 後重送仍 401 `invalid_token`):app 要清掉 session、回到登入頁。
    func sessionDidExpire() async
}
