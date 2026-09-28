import MyMoneyDomain

/// 不連網路的機器人記帳，記下解除的綁定與模擬對話送出的訊息。
public actor InMemoryBotRepository: BotRepository {
    private var stored: [BotBinding]
    private var failure: RepositoryError?
    private let gate: Gate?

    public private(set) var unboundIDs: [BotBindingID] = []
    public private(set) var simulatedTexts: [String] = []

    public init(bindings: [BotBinding], gate: Gate? = nil) {
        stored = bindings
        self.gate = gate
    }

    /// 綁定了一個 LINE 帳號「小明的 LINE」;綁定驗證碼是 AB12CD。
    public static func sample(gate: Gate? = nil) -> InMemoryBotRepository {
        InMemoryBotRepository(
            bindings: [BotBinding(id: BotBindingID("sample-line"), platform: .line, displayName: "小明的 LINE")],
            gate: gate
        )
    }

    public func pairingCode() async throws -> PairingCode {
        if let failure { throw failure }
        return PairingCode(code: "AB12CD", expiresInSeconds: 600)
    }

    public func bindings() async throws -> [BotBinding] {
        if let failure { throw failure }
        return stored
    }

    public func unbind(_ id: BotBindingID) async throws {
        if let failure { throw failure }
        unboundIDs.append(id)
        stored.removeAll { $0.id == id }
    }

    /// 不解析訊息，一律回「記帳成功：{訊息}」。跟後端一樣，第一次會建立「模擬測試助手」的 LINE 綁定。
    public func simulate(_ text: String) async throws -> String {
        await gate?.pass()
        if let failure { throw failure }
        simulatedTexts.append(text)
        let simulated = BotBindingID("simulated-helper")
        if !stored.contains(where: { $0.id == simulated }) {
            stored.append(BotBinding(id: simulated, platform: .line, displayName: "模擬測試助手"))
        }
        return "記帳成功：\(text)"
    }

    /// 之後的請求都以這個錯誤失敗。
    public func fail(with error: RepositoryError) {
        failure = error
    }
}
