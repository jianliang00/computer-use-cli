// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "computer-use-cli",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "ComputerUseCLI", targets: ["ComputerUseCLI"]),
        .executable(name: "computer-use", targets: ["computer-use"]),
        .library(name: "ContainerBridge", targets: ["ContainerBridge"]),
        .library(name: "AgentProtocol", targets: ["AgentProtocol"]),
        .library(name: "BootstrapAgent", targets: ["BootstrapAgent"]),
        .library(name: "ComputerUseAgentApp", targets: ["ComputerUseAgentApp"]),
        .library(name: "ComputerUseAgentCore", targets: ["ComputerUseAgentCore"]),
        .executable(name: "computer-use-agent", targets: ["computer-use-agent"]),
        .executable(name: "bootstrap-agent", targets: ["bootstrap-agent"]),
    ],
    targets: [
        .target(
            name: "ComputerUseCLI",
            dependencies: [
                "AgentProtocol",
                "ContainerBridge",
            ]
        ),
        .executableTarget(
            name: "computer-use",
            dependencies: [
                "ComputerUseCLI",
            ],
            path: "Sources/computer-use"
        ),
        .target(name: "ContainerBridge"),
        .target(name: "AgentProtocol"),
        .target(
            name: "BootstrapAgent",
            dependencies: [
                "AgentProtocol",
            ]
        ),
        .target(
            name: "ComputerUseAgentCore",
            dependencies: [
                "AgentProtocol",
            ]
        ),
        .target(
            name: "ComputerUseAgentApp",
            dependencies: [
                "AgentProtocol",
                "ComputerUseAgentCore",
            ]
        ),
        .executableTarget(
            name: "computer-use-agent",
            dependencies: [
                "ComputerUseAgentApp",
                "ComputerUseAgentCore",
            ],
            path: "Sources/computer-use-agent"
        ),
        .executableTarget(
            name: "bootstrap-agent",
            dependencies: [
                "BootstrapAgent",
            ],
            path: "Sources/bootstrap-agent"
        ),
        .testTarget(
            name: "ComputerUseCLITests",
            dependencies: [
                "AgentProtocol",
                "ComputerUseCLI",
            ]
        ),
        .testTarget(
            name: "ContainerBridgeTests",
            dependencies: [
                "ContainerBridge",
            ]
        ),
        .testTarget(
            name: "AgentProtocolTests",
            dependencies: [
                "AgentProtocol",
            ]
        ),
        .testTarget(
            name: "ComputerUseAgentCoreTests",
            dependencies: [
                "AgentProtocol",
                "BootstrapAgent",
                "ComputerUseAgentApp",
                "ComputerUseAgentCore",
            ]
        ),
    ]
)
