import Foundation
import MyMoneyDomain
import Observation

/// 模擬對話的一則訊息。
public struct ChatMessage: Identifiable, Sendable {
    public enum Sender: Sendable {
        case user
        case bot
    }

    public let id = UUID()
    public let sender: Sender
    public let text: String
    public let time: Date
    public let isError: Bool
}

/// 帳號 sheet → 機器人記帳(parity.md「機器人記帳」)。
@MainActor
@Observable
public final class BotModel {
    /// 跟 web 一樣的 4 個快捷範例。
    public static let examples = ["午餐 120", "一蘭拉麵 320 現金", "薪水 65000 銀行", "查帳"]
    /// 正確的 webhook 網址(parity 刻意偏離第 8 項:web 多了 /api,網域也不對)。
    public static let lineWebhook = "https://my-money-api.onion523.workers.dev/bot/webhook/line"
    public static let telegramWebhook = "https://my-money-api.onion523.workers.dev/bot/webhook/telegram"

    /// 載入之前是 `nil`,畫面不會先顯示「尚未綁定」。
    public private(set) var bindings: [BotBinding]?
    public private(set) var messages: [ChatMessage]
    public var draft = ""
    public private(set) var isThinking = false
    /// 操作失敗時顯示的訊息(alert)。
    public var alertMessage: String?

    private var pairingCode: String?
    private var pairingExpiresAt: Date?

    @ObservationIgnored private let repository: any BotRepository
    @ObservationIgnored private let dataVersion: DataVersion
    @ObservationIgnored private let now: () -> Date

    public init(repository: any BotRepository, dataVersion: DataVersion, now: @escaping () -> Date = { .now }) {
        self.repository = repository
        self.dataVersion = dataVersion
        self.now = now
        messages = [ChatMessage(
            sender: .bot,
            text: "您好！我是記帳小幫手。可以試著傳送「午餐 120」或「查帳」。",
            time: now(),
            isError: false
        )]
    }

    private var remainingSeconds: Int {
        guard let pairingExpiresAt else { return 0 }
        return max(Int(pairingExpiresAt.timeIntervalSince(now()).rounded(.up)), 0)
    }

    /// 還沒過期的綁定驗證碼;過期或還沒產生時是 `nil`。
    public var visiblePairingCode: String? { remainingSeconds > 0 ? pairingCode : nil }

    /// 剩下的時間，例如「9 分 59 秒」。畫面每秒重算一次。
    public var countdownText: String { "\(remainingSeconds / 60) 分 \(remainingSeconds % 60) 秒" }

    /// 「複製指令」複製的內容。
    public var pairingCommand: String { "綁定 \(pairingCode ?? "")" }

    public func unbindConfirmation(for binding: BotBinding) -> String {
        let name = binding.displayName.map { "「\($0)」" } ?? ""
        return "確定要解除 \(binding.platform.title)\(name)的機器人綁定嗎？"
    }

    /// 已綁定的帳號載入失敗的原因;畫面在那一區顯示它和「重試」,不再停在骨架屏。
    public private(set) var bindingsErrorMessage: String?

    /// 已綁定的帳號第一次載入中(顯示骨架屏)。
    public var isLoadingBindings: Bool { bindings == nil && bindingsErrorMessage == nil }

    public func load() async {
        do {
            bindings = try await repository.bindings()
            bindingsErrorMessage = nil
        } catch {
            bindingsErrorMessage = error.localizedDescription
        }
    }

    /// 產生新的綁定驗證碼;之前的會失效。
    public func generatePairingCode() async {
        do {
            let code = try await repository.pairingCode()
            pairingCode = code.code
            pairingExpiresAt = now().addingTimeInterval(TimeInterval(code.expiresInSeconds))
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    public func unbind(_ binding: BotBinding) async {
        do {
            try await repository.unbind(binding.id)
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        await load()
    }

    /// 送出一則訊息。寫入的是真的交易紀錄，所以成功後資料版本遞增;錯誤以一則訊息泡泡呈現。
    public func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        draft = ""
        messages.append(ChatMessage(sender: .user, text: text, time: now(), isError: false))
        isThinking = true
        defer { isThinking = false }
        do {
            let reply = try await repository.simulate(text)
            messages.append(ChatMessage(sender: .bot, text: reply, time: now(), isError: false))
            dataVersion.bump()
            // 後端第一次模擬對話時會建立「模擬測試助手」的綁定;重抓失敗就沿用原本的清單。
            if let latest = try? await repository.bindings() { bindings = latest }
        } catch {
            let message = error.localizedDescription
            messages.append(ChatMessage(
                sender: .bot, text: "錯誤：\(message.isEmpty ? "無法處理請求" : message)", time: now(), isError: true
            ))
        }
    }
}

extension BotPlatform {
    public var title: String {
        switch self {
        case .line: "LINE"
        case .telegram: "Telegram"
        }
    }
}
