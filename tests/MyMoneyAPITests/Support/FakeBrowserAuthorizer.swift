import Foundation
import MyMoneyDomain
import Synchronization

/// 假的系統登入視窗:記下開過的授權網址,回應由測試決定(照網址裡的 `state` 導回 code、導回固定網址、或使用者取消)。
final class FakeBrowserAuthorizer: BrowserAuthorizer {
    enum Outcome: Sendable {
        /// 登入成功:導回 `callback?code=…&state=<授權網址的 state>`。
        case code(String)
        /// 導回固定的 callback(例如帶 `error`,或 `state` 不符)。
        case callback(String)
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
        case .code(let code):
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "state" }?.value ?? ""
            return URL(string: "com.raychiu.mymoney:/oauth/callback?code=\(code)&state=\(state)")!
        case .callback(let callback):
            return URL(string: callback)!
        case .cancelled:
            throw CancellationError()
        }
    }
}
