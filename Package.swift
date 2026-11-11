// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentBarCore", targets: ["AgentBarCore"]),
        .library(name: "ClaudeProvider", targets: ["ClaudeProvider"]),
        .library(name: "CodexProvider", targets: ["CodexProvider"]),
        .executable(name: "AgentBar", targets: ["AgentBar"]),
        .executable(name: "agentbar-probe", targets: ["AgentBarProbe"]),
    ],
    targets: [
        .target(name: "AgentBarCore"),
        .target(name: "ClaudeProvider", dependencies: ["AgentBarCore"], exclude: ["README.md"]),
        .target(name: "CodexProvider", dependencies: ["AgentBarCore"], exclude: ["README.md"]),
        .executableTarget(
            name: "AgentBar",
            dependencies: ["AgentBarCore", "ClaudeProvider", "CodexProvider"]
        ),
        .executableTarget(
            name: "AgentBarProbe",
            dependencies: ["AgentBarCore", "ClaudeProvider", "CodexProvider"]
        ),
        .testTarget(name: "AgentBarCoreTests", dependencies: ["AgentBarCore"]),
        .testTarget(name: "ClaudeProviderTests", dependencies: ["ClaudeProvider"]),
        .testTarget(name: "CodexProviderTests", dependencies: ["CodexProvider"]),
        .testTarget(name: "AgentBarTests", dependencies: ["AgentBar"]),
    ],
    swiftLanguageModes: [.v6]
)
