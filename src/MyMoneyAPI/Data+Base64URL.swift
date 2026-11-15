import Foundation

/// MyMoneyAPI 共用的 base64url 編解碼(WebAuthn、PKCE、DPoP proof)。
extension Data {
    /// base64url、不補 `=`(RFC 4648 §5,WebAuthn、PKCE 與 DPoP 用的格式)。
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
