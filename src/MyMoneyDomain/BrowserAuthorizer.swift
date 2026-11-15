import Foundation

/// 「瀏覽器授權」:在系統的安全登入視窗開授權網址,使用者完成後回傳導回 app 的 callback URL。
/// App 層用 AuthenticationServices(`ASWebAuthenticationSession`)實作,測試用假物件。
public protocol BrowserAuthorizer: Sendable {
    /// 使用者關掉登入視窗時丟 `CancellationError`。
    func authorize(url: URL, callbackScheme: String) async throws -> URL
}
