import Foundation
import MyMoneyDomain
import Synchronization

/// 假的 passkey 驗證器:記下收到的請求,回固定的 registration,或使用者取消。
final class FakePasskeyAuthenticator: PasskeyAuthenticator {
    struct RegistrationCall: Equatable {
        let relyingPartyID: String
        let challenge: Data
        let userID: Data
        let userName: String
    }

    static let registration = PasskeyRegistration(
        credentialID: Data([0xFB, 0xFF, 0x02]), clientDataJSON: Data("{\"type\":\"webauthn.create\"}".utf8),
        attestationObject: Data([0xA3, 0x63, 0xFF])
    )

    private let cancels: Bool
    private let calls = Mutex<[RegistrationCall]>([])

    init(cancels: Bool = false) {
        self.cancels = cancels
    }

    var registrations: [RegistrationCall] { calls.withLock { $0 } }

    func registration(relyingPartyID: String, challenge: Data, userID: Data, userName: String) async throws -> PasskeyRegistration {
        calls.withLock {
            $0.append(RegistrationCall(relyingPartyID: relyingPartyID, challenge: challenge, userID: userID, userName: userName))
        }
        if cancels { throw CancellationError() }
        return Self.registration
    }
}
