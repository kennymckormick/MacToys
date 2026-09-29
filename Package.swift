// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InputStats",
    platforms: [.macOS(.v14)],
    targets: [
        // 纯逻辑（可单元测试）：计数、分词、聚合。
        .target(name: "InputStatsCore", path: "Sources/InputStatsCore"),
        .target(name: "InputStatsStorage", dependencies: ["InputStatsCore"], linkerSettings: [.linkedLibrary("sqlite3")]),
        // 可执行 app：UI + 系统监听 + 存储。
        .executableTarget(
            name: "InputStats",
            dependencies: ["InputStatsCore", "InputStatsStorage"],
            path: "Sources/InputStats",
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedFramework("Carbon")]
        ),
        // 自检（无需 Xcode/XCTest）：swift run SelfCheck
        .executableTarget(
            name: "SelfCheck",
            dependencies: ["InputStatsCore", "InputStatsStorage"],
            path: "Tests/SelfCheck"
        ),
    ]
)
