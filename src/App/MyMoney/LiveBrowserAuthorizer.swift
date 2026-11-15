import AuthenticationServices
import MyMoneyDomain
import UIKit

/// 「瀏覽器授權」的系統實作(#334):用 `ASWebAuthenticationSession` 開上游 Worker 的登入頁。
///
/// `prefersEphemeralWebBrowserSession`:授權伺服器本來就不保留長效 cookie,也避免出現「要使用某網站登入」的確認(#332)。
struct LiveBrowserAuthorizer: BrowserAuthorizer {
    @MainActor
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        let anchor = PresentationAnchor()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    // 使用者關掉登入視窗:不是錯誤。
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? CancellationError())
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = anchor
            if !session.start() {
                continuation.resume(throwing: CancellationError())
            }
        }
    }
}

/// 登入視窗與 passkey 視窗(`LivePasskeyAuthenticator`)疊在目前的 key window 上。
final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding,
    ASAuthorizationControllerPresentationContextProviding {
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        keyWindow()
    }

    @MainActor
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        keyWindow()
    }

    @MainActor
    private func keyWindow() -> ASPresentationAnchor {
        // 按得到登入鈕就一定有 window scene。
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? ASPresentationAnchor(windowScene: scenes[0])
    }
}
