import Foundation
import MyMoneyDomain

/// Passkey 管理(`/auth/passkey/register/*`、`/auth/passkeys`,#339)的 URLSession 實作。
/// 建立時由 `PasskeyAuthenticator` 產生 registration,這裡只負責 options 與 WebAuthn JSON(base64url)的翻譯。
public struct LivePasskeyRepository: PasskeyRepository {
    private let client: APIClient
    private let authenticator: any PasskeyAuthenticator

    public init(client: APIClient, authenticator: any PasskeyAuthenticator) {
        self.client = client
        self.authenticator = authenticator
    }

    public func passkeys() async throws -> [Passkey] {
        let dtos: [PasskeyDTO] = try await client.get("/auth/passkeys")
        return dtos.map { dto in
            Passkey(
                id: PasskeyID(dto.id), name: dto.name, createdAt: Date(timeIntervalSince1970: dto.createdAt),
                lastUsedAt: dto.lastUsedAt.map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    public func create(name: String) async throws {
        let options: RegistrationOptionsDTO = try await client.send("POST", "/auth/passkey/register/options", body: [String: String]())
        guard
            let challenge = Data(base64URLEncoded: options.challenge),
            let userID = Data(base64URLEncoded: options.user.id)
        else { throw RepositoryError.unreadableResponse }
        let registration = try await authenticator.registration(
            relyingPartyID: options.rp.id, challenge: challenge, userID: userID, userName: options.user.name
        )
        try await client.send("POST", "/auth/passkey/register/verify", body: RegistrationVerifyRequest(
            response: WebAuthnCredentialJSON(credentialID: registration.credentialID, response: AttestationJSON(
                clientDataJSON: registration.clientDataJSON.base64URLEncodedString(),
                attestationObject: registration.attestationObject.base64URLEncodedString()
            )),
            name: name
        ))
    }

    public func rename(_ id: PasskeyID, to name: String) async throws {
        try await client.send("PATCH", "/auth/passkeys/\(id.rawValue)", body: ["name": name])
    }

    public func delete(_ id: PasskeyID) async throws {
        try await client.send("DELETE", "/auth/passkeys/\(id.rawValue)")
    }
}

/// `GET /auth/passkeys` 的一筆:snake_case,時間是 Unix 秒,沒用過的 `last_used_at` 是 `null`。
private struct PasskeyDTO: Decodable {
    let id: String
    let name: String
    let createdAt: TimeInterval
    let lastUsedAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }
}

/// SimpleWebAuthn 的 registration options 裡用得到的部分;`challenge` 與 `user.id` 是 base64url。
private struct RegistrationOptionsDTO: Decodable {
    struct RelyingParty: Decodable { let id: String }
    struct User: Decodable {
        let id: String
        let name: String
    }

    let challenge: String
    let rp: RelyingParty
    let user: User
}

private struct RegistrationVerifyRequest: Encodable {
    let response: WebAuthnCredentialJSON<AttestationJSON>
    let name: String
}

private struct AttestationJSON: Encodable {
    let clientDataJSON: String
    let attestationObject: String
}

/// WebAuthn 的 `PublicKeyCredential` JSON(SimpleWebAuthn 的 `*ResponseJSON`):二進位欄位都是 base64url。
struct WebAuthnCredentialJSON<Response: Encodable>: Encodable {
    let id: String
    let rawId: String
    let type = "public-key"
    let response: Response
    let clientExtensionResults: [String: String] = [:]

    init(credentialID: Data, response: Response) {
        id = credentialID.base64URLEncodedString()
        rawId = id
        self.response = response
    }
}

extension Data {
    /// base64url、不補 `=`(RFC 4648 §5,WebAuthn 與 PKCE 用的格式)。
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
