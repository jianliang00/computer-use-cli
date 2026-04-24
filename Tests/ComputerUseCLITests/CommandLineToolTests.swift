import ComputerUseCLI
import ContainerBridge
import Foundation
import Testing

@Test
func machineCreateAndInspectRoundTrip() throws {
    let homeDirectory = try temporaryDirectory()
    let tool = CommandLineTool(
        fileManager: .default,
        homeDirectory: homeDirectory,
        now: { Date(timeIntervalSince1970: 1_710_000_000) },
        containerBridge: StubContainerBridge()
    )

    let created = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "demo",
        "--image", "local/computer-use:authorized",
    ])
    #expect(created.contains("\"name\" : \"demo\""))
    #expect(created.contains("\"hostPort\" : 46000"))

    let inspected = try tool.run(arguments: [
        "machine",
        "inspect",
        "--machine", "demo",
    ])
    #expect(inspected.contains("\"imageReference\" : \"local/computer-use:authorized\""))
}

@Test
func machineListReturnsStoredMachines() throws {
    let homeDirectory = try temporaryDirectory()
    let tool = CommandLineTool(
        fileManager: .default,
        homeDirectory: homeDirectory,
        now: { Date(timeIntervalSince1970: 1_710_000_100) },
        containerBridge: StubContainerBridge()
    )

    _ = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "alpha",
        "--image", "local/computer-use:authorized",
    ])
    _ = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "beta",
        "--image", "local/computer-use:product",
    ])

    let listOutput = try tool.run(arguments: ["machine", "list"])
    #expect(listOutput.contains("\"name\" : \"alpha\""))
    #expect(listOutput.contains("\"name\" : \"beta\""))
}

@Test
func machineLifecycleCommandsUseTheBridge() throws {
    let homeDirectory = try temporaryDirectory()
    let bridge = StubContainerBridge()
    let tool = CommandLineTool(
        fileManager: .default,
        homeDirectory: homeDirectory,
        now: { Date(timeIntervalSince1970: 1_710_000_200) },
        containerBridge: bridge
    )

    _ = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "demo",
        "--image", "local/computer-use:authorized",
    ])

    let started = try tool.run(arguments: [
        "machine",
        "start",
        "--machine", "demo",
        "--",
        "tail",
        "-f",
        "/dev/null",
    ])
    #expect(started.contains("\"sandboxID\" : \"demo\""))
    #expect(started.contains("\"status\" : \"running\""))
    #expect(bridge.createdConfigurations.first?.initProcessArguments == ["tail", "-f", "/dev/null"])

    let logs = try tool.run(arguments: [
        "machine",
        "logs",
        "--machine", "demo",
    ])
    #expect(logs == "bootstrap ok\nagent ready")

    let stopped = try tool.run(arguments: [
        "machine",
        "stop",
        "--machine", "demo",
    ])
    #expect(stopped.contains("\"status\" : \"stopped\""))

    let removed = try tool.run(arguments: [
        "machine",
        "rm",
        "--machine", "demo",
    ])
    #expect(removed == "removed demo")
}

@Test
func machineInspectRepairsMetadataWhenSandboxAlreadyExists() throws {
    let homeDirectory = try temporaryDirectory()
    let bridge = ExistingSandboxBridge()
    let tool = CommandLineTool(
        fileManager: .default,
        homeDirectory: homeDirectory,
        now: { Date(timeIntervalSince1970: 1_710_000_300) },
        containerBridge: bridge
    )

    _ = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "demo",
        "--image", "local/computer-use:authorized",
    ])

    let inspected = try tool.run(arguments: [
        "machine",
        "inspect",
        "--machine", "demo",
    ])

    #expect(inspected.contains("\"sandboxID\" : \"demo\""))
    #expect(inspected.contains("\"status\" : \"stopped\""))
}

@Test
func machineStartPersistsCreatedSandboxWhenStartFails() throws {
    let homeDirectory = try temporaryDirectory()
    let bridge = StartFailureBridge()
    let tool = CommandLineTool(
        fileManager: .default,
        homeDirectory: homeDirectory,
        now: { Date(timeIntervalSince1970: 1_710_000_400) },
        containerBridge: bridge
    )

    _ = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "demo",
        "--image", "local/computer-use:authorized",
    ])

    do {
        _ = try tool.run(arguments: [
            "machine",
            "start",
            "--machine", "demo",
            "--",
            "tail",
            "-f",
            "/dev/null",
        ])
        Issue.record("expected start to fail")
    } catch let error as ContainerBridgeError {
        #expect(error == .commandFailed(
            command: ["start", "demo"],
            exitCode: 1,
            stderr: "bootstrap failed"
        ))
    }

    let inspected = try tool.run(arguments: [
        "machine",
        "inspect",
        "--machine", "demo",
    ])
    #expect(inspected.contains("\"sandboxID\" : \"demo\""))
    #expect(inspected.contains("\"status\" : \"stopped\""))
}

private func temporaryDirectory() throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

private final class StubContainerBridge: ContainerRuntimeBridging, @unchecked Sendable {
    private var states: [String: SandboxDetails.Status] = [:]
    private(set) var createdConfigurations: [SandboxConfiguration] = []

    func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails {
        createdConfigurations.append(configuration)
        states[configuration.name] = .stopped
        return SandboxDetails(
            sandboxID: configuration.name,
            name: configuration.name,
            imageReference: configuration.imageReference,
            publishedHostPort: configuration.publishedHostPort,
            status: .stopped
        )
    }

    func startSandbox(id: String) throws -> SandboxDetails {
        states[id] = .running
        return details(for: id, status: .running)
    }

    func inspectSandbox(id: String) throws -> SandboxDetails {
        guard let state = states[id] else {
            throw ContainerBridgeError.sandboxNotFound(id)
        }

        return details(for: id, status: state)
    }

    func stopSandbox(id: String) throws -> SandboxDetails {
        states[id] = .stopped
        return details(for: id, status: .stopped)
    }

    func removeSandbox(id: String) throws {
        states.removeValue(forKey: id)
    }

    func queryLogs(id: String) throws -> SandboxLogs {
        SandboxLogs(
            sandboxID: id,
            entries: [
                "bootstrap ok",
                "agent ready",
            ]
        )
    }

    func resolvePublishedHostPort(id: String) throws -> Int {
        46000
    }

    private func details(for id: String, status: SandboxDetails.Status) -> SandboxDetails {
        SandboxDetails(
            sandboxID: id,
            name: id,
            imageReference: "local/computer-use:authorized",
            publishedHostPort: 46000,
            status: status
        )
    }
}

private struct ExistingSandboxBridge: ContainerRuntimeBridging {
    func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails {
        throw ContainerBridgeError.commandFailed(
            command: ["create"],
            exitCode: 1,
            stderr: "create should not be called"
        )
    }

    func startSandbox(id: String) throws -> SandboxDetails {
        throw ContainerBridgeError.commandFailed(
            command: ["start"],
            exitCode: 1,
            stderr: "start should not be called"
        )
    }

    func inspectSandbox(id: String) throws -> SandboxDetails {
        SandboxDetails(
            sandboxID: id,
            name: id,
            imageReference: "local/computer-use:authorized",
            publishedHostPort: 46000,
            status: .stopped
        )
    }

    func stopSandbox(id: String) throws -> SandboxDetails {
        try inspectSandbox(id: id)
    }

    func removeSandbox(id: String) throws {}

    func queryLogs(id: String) throws -> SandboxLogs {
        SandboxLogs(sandboxID: id, entries: [])
    }

    func resolvePublishedHostPort(id: String) throws -> Int {
        46000
    }
}

private final class StartFailureBridge: ContainerRuntimeBridging, @unchecked Sendable {
    private var createdIDs: Set<String> = []

    func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails {
        createdIDs.insert(configuration.name)
        return details(for: configuration.name, status: .stopped)
    }

    func startSandbox(id: String) throws -> SandboxDetails {
        throw ContainerBridgeError.commandFailed(
            command: ["start", id],
            exitCode: 1,
            stderr: "bootstrap failed"
        )
    }

    func inspectSandbox(id: String) throws -> SandboxDetails {
        guard createdIDs.contains(id) else {
            throw ContainerBridgeError.sandboxNotFound(id)
        }

        return details(for: id, status: .stopped)
    }

    func stopSandbox(id: String) throws -> SandboxDetails {
        try inspectSandbox(id: id)
    }

    func removeSandbox(id: String) throws {
        createdIDs.remove(id)
    }

    func queryLogs(id: String) throws -> SandboxLogs {
        SandboxLogs(sandboxID: id, entries: [])
    }

    func resolvePublishedHostPort(id: String) throws -> Int {
        46000
    }

    private func details(for id: String, status: SandboxDetails.Status) -> SandboxDetails {
        SandboxDetails(
            sandboxID: id,
            name: id,
            imageReference: "local/computer-use:authorized",
            publishedHostPort: 46000,
            status: status
        )
    }
}
