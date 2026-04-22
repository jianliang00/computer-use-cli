import Foundation

public struct SandboxConfiguration: Equatable, Sendable {
    public let name: String
    public let imageReference: String
    public let publishedHostPort: Int
    public let guestAgentPort: Int
    public let hostAddress: String
    public let guiEnabled: Bool

    public init(
        name: String,
        imageReference: String,
        publishedHostPort: Int,
        guestAgentPort: Int = 7777,
        hostAddress: String = "127.0.0.1",
        guiEnabled: Bool = true
    ) {
        self.name = name
        self.imageReference = imageReference
        self.publishedHostPort = publishedHostPort
        self.guestAgentPort = guestAgentPort
        self.hostAddress = hostAddress
        self.guiEnabled = guiEnabled
    }

    var publishSpec: String {
        "\(hostAddress):\(publishedHostPort):\(guestAgentPort)/tcp"
    }
}

public struct SandboxDetails: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case created
        case running
        case stopped

        init(containerStatus: String) {
            switch containerStatus.lowercased() {
            case "running":
                self = .running
            case "created":
                self = .created
            default:
                self = .stopped
            }
        }
    }

    public let sandboxID: String
    public let name: String
    public let imageReference: String
    public let publishedHostPort: Int
    public let status: Status

    public init(
        sandboxID: String,
        name: String,
        imageReference: String,
        publishedHostPort: Int,
        status: Status
    ) {
        self.sandboxID = sandboxID
        self.name = name
        self.imageReference = imageReference
        self.publishedHostPort = publishedHostPort
        self.status = status
    }
}

public struct SandboxLogs: Equatable, Sendable {
    public let sandboxID: String
    public let entries: [String]

    public init(
        sandboxID: String,
        entries: [String]
    ) {
        self.sandboxID = sandboxID
        self.entries = entries
    }
}

public protocol ContainerRuntimeBridging: Sendable {
    func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails
    func startSandbox(id: String) throws -> SandboxDetails
    func inspectSandbox(id: String) throws -> SandboxDetails
    func stopSandbox(id: String) throws -> SandboxDetails
    func removeSandbox(id: String) throws
    func queryLogs(id: String) throws -> SandboxLogs
    func resolvePublishedHostPort(id: String) throws -> Int
}

public struct ContainerCLIBridge: ContainerRuntimeBridging {
    private let runner: any ContainerCommandRunning

    public init(runner: any ContainerCommandRunning = ProcessContainerCommandRunner()) {
        self.runner = runner
    }

    public func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails {
        var arguments = [
            "create",
            "--name", configuration.name,
        ]

        if configuration.guiEnabled {
            arguments.append("--gui")
        }

        arguments.append(contentsOf: [
            "--publish", configuration.publishSpec,
            configuration.imageReference,
        ])

        let result = try runner.run(arguments: arguments)
        let sandboxID = result.stdout.isEmpty ? configuration.name : result.stdout
        return try inspectSandbox(id: sandboxID)
    }

    public func startSandbox(id: String) throws -> SandboxDetails {
        _ = try runner.run(arguments: ["start", id])
        return try inspectSandbox(id: id)
    }

    public func inspectSandbox(id: String) throws -> SandboxDetails {
        let result = try runner.run(arguments: ["inspect", id])
        let payloads = try decodeInspectPayloads(from: result.stdout)

        guard let payload = payloads.first else {
            throw ContainerBridgeError.sandboxNotFound(id)
        }

        return try SandboxDetails(payload: payload)
    }

    public func stopSandbox(id: String) throws -> SandboxDetails {
        _ = try runner.run(arguments: ["stop", id])
        return try inspectSandbox(id: id)
    }

    public func removeSandbox(id: String) throws {
        _ = try runner.run(arguments: ["delete", "--force", id])
    }

    public func queryLogs(id: String) throws -> SandboxLogs {
        let result = try runner.run(arguments: ["logs", id])
        let entries = result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        return SandboxLogs(sandboxID: id, entries: entries)
    }

    public func resolvePublishedHostPort(id: String) throws -> Int {
        try inspectSandbox(id: id).publishedHostPort
    }

    private func decodeInspectPayloads(from stdout: String) throws -> [ContainerInspectPayload] {
        let data = Data(stdout.utf8)

        do {
            return try JSONDecoder().decode([ContainerInspectPayload].self, from: data)
        } catch {
            throw ContainerBridgeError.invalidInspectPayload(stdout)
        }
    }
}

public struct UnavailableContainerBridge: ContainerRuntimeBridging {
    public init() {}

    public func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails {
        throw ContainerBridgeError.notImplemented("createSandbox")
    }

    public func startSandbox(id: String) throws -> SandboxDetails {
        throw ContainerBridgeError.notImplemented("startSandbox")
    }

    public func inspectSandbox(id: String) throws -> SandboxDetails {
        throw ContainerBridgeError.notImplemented("inspectSandbox")
    }

    public func stopSandbox(id: String) throws -> SandboxDetails {
        throw ContainerBridgeError.notImplemented("stopSandbox")
    }

    public func removeSandbox(id: String) throws {
        throw ContainerBridgeError.notImplemented("removeSandbox")
    }

    public func queryLogs(id: String) throws -> SandboxLogs {
        throw ContainerBridgeError.notImplemented("queryLogs")
    }

    public func resolvePublishedHostPort(id: String) throws -> Int {
        throw ContainerBridgeError.notImplemented("resolvePublishedHostPort")
    }
}

public enum ContainerBridgeError: Error, LocalizedError, Equatable {
    case notImplemented(String)
    case commandFailed(command: [String], exitCode: Int32, stderr: String)
    case invalidInspectPayload(String)
    case sandboxNotFound(String)
    case publishedPortNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .notImplemented(method):
            return "\(method) is not implemented yet"
        case let .commandFailed(command, exitCode, stderr):
            let renderedCommand = command.joined(separator: " ")
            let details = stderr.isEmpty ? "container command failed" : stderr
            return "\(renderedCommand) exited with code \(exitCode): \(details)"
        case let .invalidInspectPayload(output):
            return "unable to decode container inspect output: \(output)"
        case let .sandboxNotFound(id):
            return "sandbox \(id) was not found"
        case let .publishedPortNotFound(id):
            return "sandbox \(id) has no published agent port"
        }
    }
}

public protocol ContainerCommandRunning: Sendable {
    func run(arguments: [String]) throws -> CommandExecutionResult
}

public struct CommandExecutionResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct ProcessContainerCommandRunner: ContainerCommandRunning {
    private let executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/usr/local/bin/container")) {
        self.executableURL = executableURL
    }

    public func run(arguments: [String]) throws -> CommandExecutionResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(decoding: stdoutData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: stderrData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw ContainerBridgeError.commandFailed(
                command: [executableURL.path] + arguments,
                exitCode: process.terminationStatus,
                stderr: stderr
            )
        }

        return CommandExecutionResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

private struct ContainerInspectPayload: Decodable {
    struct Configuration: Decodable {
        struct Image: Decodable {
            let reference: String
        }

        struct PublishedPort: Decodable {
            let containerPort: Int
            let hostPort: Int
            let hostAddress: String?
            let proto: String?
            let count: Int?
        }

        let id: String
        let image: Image
        let publishedPorts: [PublishedPort]
    }

    let status: String
    let configuration: Configuration
}

private extension SandboxDetails {
    init(payload: ContainerInspectPayload) throws {
        guard let publishedPort = payload.configuration.publishedPorts.first else {
            throw ContainerBridgeError.publishedPortNotFound(payload.configuration.id)
        }

        self.init(
            sandboxID: payload.configuration.id,
            name: payload.configuration.id,
            imageReference: payload.configuration.image.reference,
            publishedHostPort: publishedPort.hostPort,
            status: .init(containerStatus: payload.status)
        )
    }
}
