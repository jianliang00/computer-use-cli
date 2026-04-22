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
    ])
    #expect(started.contains("\"sandboxID\" : \"demo\""))
    #expect(started.contains("\"status\" : \"running\""))

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

private func temporaryDirectory() throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

private final class StubContainerBridge: ContainerRuntimeBridging, @unchecked Sendable {
    private var states: [String: SandboxDetails.Status] = [:]

    func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails {
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
        return details(for: id, status: states[id] ?? .stopped)
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
