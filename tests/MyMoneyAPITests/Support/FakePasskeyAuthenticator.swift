import Foundation
import MyMoneyDomain
import Synchronization

/// 假的 passkey 驗證器:記下收到的請求,回固定的 assertion／registration,或使用者取消。
final class FakePasskeyAuthenticator: PasskeyAuthenticator {
    struct AssertionCall: Equatable {
        let relyingPartyID: String
        let challenge: Data
    }

    struct RegistrationCall: Equatable {
        let relyingPartyID: String
        let challenge: Data
        let userID: Data
        let userName: String
    }

    static let assertion = PasskeyAssertion(
        credentialID: Data([0xFB, 0xFF, 0x01]), clientDataJSON: Data("{\"type\":\"webauthn.get\"}".utf8),
        authenticatorData: Data([0x49, 0x96, 0x0D]), signature: Data([0x30, 0x45, 0xFE]), userHandle: Data("user-handle".utf8)
    )

    static let registration = PasskeyRegistration(
        credentialID: Data([0xFB, 0xFF, 0x02]), clientDataJSON: Data("{\"type\":\"webauthn.create\"}".utf8),
        attestationObject: Data([0xA3, 0x63, 0xFF])
    )

    private let cancels: Bool
    private let calls = Mutex<(assertions: [AssertionCall], registrations: [RegistrationCall])>(([], []))

    init(cancels: Bool = false) {
        self.cancels = cancels
    }

    var assertions: [AssertionCall] { calls.withLock { $0.assertions } }
    var registrations: [RegistrationCall] { calls.withLock { $0.registrations } }

    func assertion(relyingPartyID: String, challenge: Data) async throws -> PasskeyAssertion {
        calls.withLock { $0.assertions.append(AssertionCall(relyingPartyID: relyingPartyID, challenge: challenge)) }
        if cancels { throw CancellationError() }
        return Self.assertion
    }

    func registration(relyingPartyID: String, challenge: Data, userID: Data, userName: String) async throws -> PasskeyRegistration {
        calls.withLock {
            $0.registrations.append(RegistrationCall(relyingPartyID: relyingPartyID, challenge: challenge, userID: userID, userName: userName))
        }
        if cancels { throw CancellationError() }
        return Self.registration
    }
}
