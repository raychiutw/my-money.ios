import LocalAuthentication
import MyMoneyDomain

/// 真實的驗證器(#298):系統的 LocalAuthentication,策略是「裝置擁有者驗證」——生物辨識為主,
/// 失敗或被鎖住可以改用裝置密碼,不會把人鎖在 app 外面。純本機,不碰後端。
struct LiveDeviceAuthenticator: DeviceAuthenticator {
    func capability() async -> DeviceAuthCapability {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcodeOnly
        }
    }

    func authenticate(reason: String) async -> DeviceAuthResult {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return ok ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled: return .unavailable
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}
