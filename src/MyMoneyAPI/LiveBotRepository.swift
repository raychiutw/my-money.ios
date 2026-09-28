import Foundation
import MyMoneyDomain

/// `/bot` 的 URLSession 實作。
public struct LiveBotRepository: BotRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func pairingCode() async throws -> PairingCode {
        let dto: PairingCodeDTO = try await client.send("POST", "/bot/pairing-code")
        return PairingCode(code: dto.code, expiresInSeconds: dto.expiresInSeconds)
    }

    public func bindings() async throws -> [BotBinding] {
        let dtos: [BindingDTO] = try await client.get("/bot/bindings")
        return try dtos.map { dto in
            guard let platform = BotPlatform(rawValue: dto.platform) else { throw RepositoryError.unreadableResponse }
            return BotBinding(id: BotBindingID(dto.id), platform: platform, displayName: dto.displayName)
        }
    }

    /// 後端只回 `{success, message}`,沒有 `data`。
    public func unbind(_ id: BotBindingID) async throws {
        try await client.send("DELETE", "/bot/bindings/\(id.rawValue)")
    }

    /// 跟 web 一樣用 LINE 的格式模擬。
    public func simulate(_ text: String) async throws -> String {
        let dto: SimulateDTO = try await client.send("POST", "/bot/test-simulate", body: ["text": text, "platform": "line"])
        return dto.reply
    }
}

private struct PairingCodeDTO: Decodable {
    let code: String
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case code
        case expiresInSeconds = "expires_in_seconds"
    }
}

private struct BindingDTO: Decodable {
    let id: String
    let platform: String
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id, platform
        case displayName = "display_name"
    }
}

private struct SimulateDTO: Decodable {
    let reply: String
}
