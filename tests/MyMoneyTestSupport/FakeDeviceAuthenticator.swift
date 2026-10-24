import MyMoneyDomain

/// 測試與 `-uiTesting` 用的假驗證器:能力與驗證結果都可以設定,並記下被要求驗證幾次。
public actor FakeDeviceAuthenticator: DeviceAuthenticator {
    public var capabilityValue: DeviceAuthCapability
    public var result: DeviceAuthResult
    public private(set) var authenticateCount = 0

    public init(capability: DeviceAuthCapability = .faceID, result: DeviceAuthResult = .success) {
        capabilityValue = capability
        self.result = result
    }

    public func setCapability(_ capability: DeviceAuthCapability) { capabilityValue = capability }
    public func setResult(_ result: DeviceAuthResult) { self.result = result }

    public func capability() async -> DeviceAuthCapability { capabilityValue }

    public func authenticate(reason: String) async -> DeviceAuthResult {
        authenticateCount += 1
        return result
    }
}
