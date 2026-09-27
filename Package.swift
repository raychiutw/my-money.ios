// swift-tools-version: 6.2
// 依賴方向由 target 宣告強制(ADR-0001、ADR-0002):
// App → Features → Domain ← API ← App。Features 不依賴 API,所以 View 碰不到 DTO。
// CI 另外用 `swift test --explicit-target-dependency-import-check error` 把關，
// 避免增量建置放過「沒宣告依賴卻 import」的違規。
import PackageDescription

/// warning 一律當 error(CLAUDE.md 完成定義)。
let strictSettings: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "MyMoney",
    // 加上 macOS 26,才能在 Mac 上直接跑 `swift test`(Observation 需要)。
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "MyMoneyDomain", targets: ["MyMoneyDomain"]),
        .library(name: "MyMoneyAPI", targets: ["MyMoneyAPI"]),
    ],
    targets: [
        .target(
            name: "MyMoneyDomain",
            path: "src/MyMoneyDomain",
            swiftSettings: strictSettings
        ),
        .target(
            name: "MyMoneyAPI",
            dependencies: ["MyMoneyDomain"],
            path: "src/MyMoneyAPI",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "MyMoneyDomainTests",
            dependencies: ["MyMoneyDomain"],
            path: "tests/MyMoneyDomainTests",
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "MyMoneyAPITests",
            dependencies: ["MyMoneyAPI", "MyMoneyDomain"],
            path: "tests/MyMoneyAPITests",
            resources: [.copy("Fixtures")],
            swiftSettings: strictSettings
        ),
    ]
)
