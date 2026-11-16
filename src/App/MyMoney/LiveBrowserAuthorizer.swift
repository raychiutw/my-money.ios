import AuthenticationServices
import MyMoneyDomain
import Synchronization
import UIKit

/// 「瀏覽器授權」的系統實作(#334):用 `ASWebAuthenticationSession` 開上游 Worker 的登入頁。
///
/// `prefersEphemeralWebBrowserSession`:授權伺服器本來就不保留長效 cookie,也避免出現「要使用某網站登入」的確認(#332)。
struct LiveBrowserAuthorizer: BrowserAuthorizer {
    @MainActor
    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        let anchor = PresentationAnchor()
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) { callback, error in
                if let callback {
                    once.resume(with: .success(callback))
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    // 使用者關掉登入視窗:不是錯誤。
                    once.resume(with: .failure(CancellationError()))
                } else {
                    once.resume(with: .failure(error ?? CancellationError()))
                }
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = anchor
            // 開不起來不能當成「使用者關掉」:關掉會自動再開(#356),會一直重開。
            if !session.start() {
                once.resume(with: .failure(RepositoryError.rejected("無法開啟登入視窗，請再試一次")))
            }
        }
    }
}

/// `start()` 回 false 之後,系統還會帶錯誤呼叫 completion handler;continuation 只能 resume 一次，第二次會當機(#351)。
private final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<URL, any Error>?>

    init(_ continuation: CheckedContinuation<URL, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(with result: Result<URL, any Error>) {
        continuation.withLock { $0.take() }?.resume(with: result)
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
