import Foundation
import MyMoneyDomain
import Synchronization

/// 假的系統登入視窗:記下開過的授權網址,回應由測試決定(照網址裡的 `state` 導回 code、導回固定網址、或使用者取消)。
final class FakeBrowserAuthorizer: BrowserAuthorizer {
    enum Outcome: Sendable {
        /// 登入成功:導回 `callback?code=…&state=<授權網址的 state>`;`biometric` 時多帶 `biometric=1`(按了「用 Face ID 登入」,#355)。
        case code(String, biometric: Bool = false)
        /// 導回固定的 callback(例如帶 `error`,或 `state` 不符)。
        case callback(String)
        /// 舊版登入頁的「用 Face ID 登入」:導回 `callback?error=passkey_requested&…&state=<授權網址的 state>`(上游 ADR 0042,#353 起不再產生)。
        case passkeyRequested
        case cancelled
    }

    private struct Opened {
        let url: URL
        let scheme: String
    }

    private let outcome: Outcome
    private let opened = Mutex<[Opened]>([])

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    var openedURLs: [URL] { opened.withLock { $0.map(\.url) } }
    var callbackSchemes: [String] { opened.withLock { $0.map(\.scheme) } }

    func authorize(url: URL, callbackScheme: String) async throws -> URL {
        opened.withLock { $0.append(Opened(url: url, scheme: callbackScheme)) }
        switch outcome {
        case .code(let code, let biometric):
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            return URL(string: "com.raychiu.mymoney:/oauth/callback?code=\(code)&state=\(state)\(biometric ? "&biometric=1" : "")")!
        case .passkeyRequested:
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            return URL(string: "com.raychiu.mymoney:/oauth/callback?error=passkey_requested&error_description=x&state=\(state)")!
        case .callback(let callback):
            return URL(string: callback)!
        case .cancelled:
            throw CancellationError()
        }
    }
}
