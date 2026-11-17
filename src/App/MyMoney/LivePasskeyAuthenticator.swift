import AuthenticationServices
import MyMoneyDomain
import UIKit

/// 「passkey 驗證器」的系統實作(#339):`ASAuthorizationPlatformPublicKeyCredentialProvider`,Face ID／Touch ID。
/// RP ID 是 web 的網域,要 Associated Domains `webcredentials:` 與上游 AASA 的 Team ID 才能在真機上使用(onion523/my-money#211)。
struct LivePasskeyAuthenticator: PasskeyAuthenticator {
    @MainActor
    func registration(relyingPartyID: String, challenge: Data, userID: Data, userName: String) async throws -> PasskeyRegistration {
        let request = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyID)
            .createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userID)
        request.userVerificationPreference = .required
        guard
            let credential = try await PasskeyAuthorization.perform(request) as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
            let attestationObject = credential.rawAttestationObject
        else {
            throw RepositoryError.rejected("Passkey 註冊驗證失敗")
        }
        return PasskeyRegistration(
            credentialID: credential.credentialID, clientDataJSON: credential.rawClientDataJSON, attestationObject: attestationObject
        )
    }
}

/// 一次 `ASAuthorizationController` 請求,把 delegate 回呼轉成 async。使用者取消丟 `CancellationError`。
@MainActor
private final class PasskeyAuthorization: NSObject, ASAuthorizationControllerDelegate {
    private var continuation: CheckedContinuation<ASAuthorizationCredential, any Error>?

    static func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorizationCredential {
        let delegate = PasskeyAuthorization()
        let anchor = PresentationAnchor()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = delegate
        controller.presentationContextProvider = anchor
        // controller 對 delegate 與 anchor 是弱參照:請求結束前(成功或失敗)要自己留住。
        defer { withExtendedLifetime((delegate, anchor, controller)) {} }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization.credential)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        if let error = error as? ASAuthorizationError, error.code == .canceled {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
