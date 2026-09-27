import MyMoneyDomain

/// `/auth/*` 的 URLSession 實作。
public struct LiveAuthRepository: AuthRepository {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func login(email: String, password: String) async throws -> Session {
        let dto: SessionDTO = try await client.send("POST", "/auth/login", body: LoginBody(email: email, password: password))
        return dto.session
    }
}

private struct LoginBody: Encodable {
    let email: String
    let password: String
}

/// `/auth/login` 與 `/auth/register` 回傳的 `data`:`{token, user: {id, email, name}}`。
private struct SessionDTO: Decodable {
    struct UserDTO: Decodable {
        let id: String
        let email: String
        let name: String
    }

    let token: String
    let user: UserDTO

    var session: Session {
        Session(token: token, user: User(id: UserID(user.id), email: user.email, name: user.name))
    }
}
