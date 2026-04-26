import Foundation

public struct SandboxConfiguration: Equatable, Sendable {
    public let name: String
    public let imageReference: String
    public let publishedHostPort: Int
    public let guestAgentPort: Int
    public let hostAddress: String
    public let guiEnabled: Bool
    public let initProcessArguments: [String]

    public init(
        name: String,
        imageReference: String,
        publishedHostPort: Int,
        guestAgentPort: Int = 7777,
        hostAddress: String = "127.0.0.1",
        guiEnabled: Bool = true,
        initProcessArguments: [String] = []
    ) {
        self.name = name
        self.imageReference = imageReference
        self.publishedHostPort = publishedHostPort
        self.guestAgentPort = guestAgentPort
        self.hostAddress = hostAddress
        self.guiEnabled = guiEnabled
        self.initProcessArguments = initProcessArguments
    }

    var publishSpec: String {
        "\(hostAddress):\(publishedHostPort):\(guestAgentPort)/tcp"
    }

    func with(initProcessArguments: [String]) -> SandboxConfiguration {
        SandboxConfiguration(
            name: name,
            imageReference: imageReference,
            publishedHostPort: publishedHostPort,
            guestAgentPort: guestAgentPort,
            hostAddress: hostAddress,
            guiEnabled: guiEnabled,
            initProcessArguments: initProcessArguments
        )
    }
}

public struct SandboxDetails: Equatable, Sendable {
    public enum AgentTransport: String, Equatable, Sendable {
        case publishedTCP = "published_tcp"
        case containerExec = "container_exec"
    }

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
    public let publishedHostPort: Int?
    public let agentTransport: AgentTransport
    public let status: Status

    public init(
        sandboxID: String,
        name: String,
        imageReference: String,
        publishedHostPort: Int?,
        agentTransport: AgentTransport = .publishedTCP,
        status: Status
    ) {
        self.sandboxID = sandboxID
        self.name = name
        self.imageReference = imageReference
        self.publishedHostPort = publishedHostPort
        self.agentTransport = agentTransport
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
    private static let defaultInitProcessArguments = ["/usr/bin/tail", "-f", "/dev/null"]

    public init(runner: any ContainerCommandRunning = ProcessContainerCommandRunner()) {
        self.runner = runner
    }

    public func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails {
        try createSandbox(configuration: configuration, includePublish: true)
    }

    private func createSandbox(
        configuration: SandboxConfiguration,
        includePublish: Bool
    ) throws -> SandboxDetails {
        let arguments = createArguments(
            configuration: configuration,
            includePublish: includePublish
        )

        do {
            let result = try runner.run(arguments: arguments)
            let sandboxID = result.stdout.isEmpty ? configuration.name : result.stdout
            return try inspectSandbox(id: sandboxID)
        } catch let error as ContainerBridgeError where error.isDarwinPublishUnsupported {
            guard includePublish else {
                throw error
            }

            return try createSandbox(
                configuration: configuration,
                includePublish: false
            )
        } catch let error as ContainerBridgeError where error.isMissingEntrypoint {
            guard configuration.initProcessArguments.isEmpty else {
                throw error
            }

            return try createSandbox(
                configuration: configuration.with(
                    initProcessArguments: Self.defaultInitProcessArguments
                ),
                includePublish: includePublish
            )
        }
    }

    private func createArguments(
        configuration: SandboxConfiguration,
        includePublish: Bool
    ) -> [String] {
        var arguments = [
            "create",
            "--name", configuration.name,
        ]

        if configuration.guiEnabled {
            arguments.append("--gui")
        }

        if includePublish {
            arguments.append(contentsOf: ["--publish", configuration.publishSpec])
        }

        arguments.append(configuration.imageReference)
        arguments.append(contentsOf: configuration.initProcessArguments)
        return arguments
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
        guard let publishedHostPort = try inspectSandbox(id: id).publishedHostPort else {
            throw ContainerBridgeError.publishedPortNotFound(id)
        }

        return publishedHostPort
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
    case runtimeBootstrapFailed(String)
    case runtimeRootMismatch(
        expectedAppRoot: String,
        expectedInstallRoot: String,
        actualAppRoot: String?,
        actualInstallRoot: String?
    )

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
        case let .runtimeBootstrapFailed(message):
            return "container runtime bootstrap failed: \(message)"
        case let .runtimeRootMismatch(expectedAppRoot, expectedInstallRoot, actualAppRoot, actualInstallRoot):
            let actualAppRoot = actualAppRoot ?? "<unknown>"
            let actualInstallRoot = actualInstallRoot ?? "<unknown>"
            return """
            container services are already running with a different root. \
            expected app root \(expectedAppRoot), install root \(expectedInstallRoot); \
            actual app root \(actualAppRoot), install root \(actualInstallRoot)
            """
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
    private let layout: ContainerRuntimeLayout
    private let bootstrapper: any ContainerRuntimeBootstrapping
    private let startsSystemServices: Bool

    public init(
        layout: ContainerRuntimeLayout = .default(),
        bootstrapper: any ContainerRuntimeBootstrapping = PublishedContainerRuntimeBootstrapper(),
        startsSystemServices: Bool = true
    ) {
        self.layout = layout
        self.bootstrapper = bootstrapper
        self.startsSystemServices = startsSystemServices
    }

    public init(executableURL: URL) {
        self.layout = ContainerRuntimeLayout(
            root: executableURL.deletingLastPathComponent().deletingLastPathComponent(),
            executableURL: executableURL
        )
        self.bootstrapper = NoopContainerRuntimeBootstrapper()
        self.startsSystemServices = false
    }

    public func run(arguments: [String]) throws -> CommandExecutionResult {
        try bootstrapper.prepareRuntime(layout: layout)
        if startsSystemServices && !isSystemCommand(arguments) {
            try ensureSystemStarted()
        }
        return try runContainer(arguments: arguments)
    }

    private func runContainer(arguments: [String]) throws -> CommandExecutionResult {
        try runProcess(executableURL: layout.executableURL, arguments: arguments)
    }

    private func runProcess(executableURL: URL, arguments: [String]) throws -> CommandExecutionResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutCollector = ProcessPipeCollector()
        let stderrCollector = ProcessPipeCollector()
        let outputGroup = DispatchGroup()

        try process.run()
        collectOutput(from: stdoutPipe, into: stdoutCollector, group: outputGroup)
        collectOutput(from: stderrPipe, into: stderrCollector, group: outputGroup)
        process.waitUntilExit()
        outputGroup.wait()

        let stdout = String(decoding: stdoutCollector.data(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: stderrCollector.data(), as: UTF8.self)
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

    private func collectOutput(
        from pipe: Pipe,
        into collector: ProcessPipeCollector,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = pipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty {
                    break
                }
                collector.append(data)
            }
            group.leave()
        }
    }

    private func isSystemCommand(_ arguments: [String]) -> Bool {
        arguments.first == "system"
    }

    private func ensureSystemStarted() throws {
        if let status = try? runContainer(arguments: ["system", "status"]),
            status.stdout.contains("apiserver is running")
        {
            let roots = ContainerSystemRoots(statusOutput: status.stdout)
            if roots.matches(layout: layout) {
                return
            }
            throw ContainerBridgeError.runtimeRootMismatch(
                expectedAppRoot: layout.appRoot.path,
                expectedInstallRoot: layout.installRoot.path,
                actualAppRoot: roots.appRoot,
                actualInstallRoot: roots.installRoot
            )
        }

        _ = try runContainer(arguments: [
            "system",
            "start",
            "--app-root", layout.appRoot.path,
            "--install-root", layout.installRoot.path,
            "--disable-kernel-install",
            "--timeout", "30",
        ])
    }
}

public struct ContainerRuntimeLayout: Equatable, Sendable {
    public static let defaultVersion = "0.0.4"
    public static let defaultReleasePackageURL = URL(
        string: "https://github.com/jianliang00/container/releases/download/\(defaultVersion)/container-installer-unsigned.pkg"
    )!

    public let version: String
    public let root: URL
    public let appRoot: URL
    public let installRoot: URL
    public let executableURL: URL
    public let releasePackageURL: URL

    public init(
        version: String = Self.defaultVersion,
        root: URL,
        appRoot: URL? = nil,
        installRoot: URL? = nil,
        executableURL: URL? = nil,
        releasePackageURL: URL? = nil
    ) {
        self.version = version
        self.root = root.standardizedFileURL
        self.appRoot = (appRoot ?? root.appendingPathComponent("app")).standardizedFileURL
        self.installRoot = (installRoot ?? root.appendingPathComponent("install")).standardizedFileURL
        self.executableURL = (executableURL ?? self.installRoot.appendingPathComponent("bin/container")).standardizedFileURL
        self.releasePackageURL = releasePackageURL ?? URL(
            string: "https://github.com/jianliang00/container/releases/download/\(version)/container-installer-unsigned.pkg"
        )!
    }

    public static func `default`(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        let version = environment["COMPUTER_USE_CONTAINER_SDK_VERSION"] ?? Self.defaultVersion
        let root = environment["COMPUTER_USE_CONTAINER_RUNTIME_ROOT"].map(URL.init(fileURLWithPath:))
            ?? homeDirectory
                .appendingPathComponent("Library/Application Support/computer-use-cli/container-sdk")
                .appendingPathComponent(version)
        return Self(
            version: version,
            root: root,
            appRoot: environment["COMPUTER_USE_CONTAINER_APP_ROOT"].map(URL.init(fileURLWithPath:)),
            installRoot: environment["COMPUTER_USE_CONTAINER_INSTALL_ROOT"].map(URL.init(fileURLWithPath:)),
            executableURL: environment["COMPUTER_USE_CONTAINER_BIN"].map(URL.init(fileURLWithPath:)),
            releasePackageURL: environment["COMPUTER_USE_CONTAINER_SDK_PKG_URL"].flatMap(URL.init(string:))
        )
    }

    var requiredPaths: [URL] {
        [
            executableURL,
            installRoot.appendingPathComponent("bin/container-apiserver"),
            installRoot.appendingPathComponent("libexec/container/macos-guest-agent/bin/container-macos-guest-agent"),
            installRoot.appendingPathComponent("libexec/container/plugins/container-runtime-macos/bin/container-runtime-macos"),
            installRoot.appendingPathComponent("libexec/container/plugins/container-runtime-macos/bin/container-runtime-macos-sidecar"),
            installRoot.appendingPathComponent("libexec/container/macos-image-prepare/bin/container-macos-image-prepare"),
            installRoot.appendingPathComponent("libexec/container/macos-vm-manager/bin/container-macos-vm-manager"),
        ]
    }
}

public protocol ContainerRuntimeBootstrapping: Sendable {
    func prepareRuntime(layout: ContainerRuntimeLayout) throws
}

public struct PublishedContainerRuntimeBootstrapper: ContainerRuntimeBootstrapping {
    public init() {}

    public func prepareRuntime(layout: ContainerRuntimeLayout) throws {
        let fm = FileManager.default
        if layout.requiredPaths.allSatisfy({ fm.isExecutableFile(atPath: $0.path) }) {
            return
        }

        let cacheRoot = layout.root.appendingPathComponent("cache")
        let workRoot = cacheRoot.appendingPathComponent("install-\(UUID().uuidString)")
        let packageFilename = layout.releasePackageURL.lastPathComponent.isEmpty
            ? "container-\(layout.version)-installer.pkg"
            : layout.releasePackageURL.lastPathComponent
        let pkgURL = cacheRoot.appendingPathComponent(packageFilename)
        let expandedURL = workRoot.appendingPathComponent("expanded")
        let stagingInstallRoot = workRoot.appendingPathComponent("install")

        do {
            try fm.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            try fm.createDirectory(at: workRoot, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: workRoot) }

            if !fm.fileExists(atPath: pkgURL.path) {
                try runHostTool(
                    executable: "/usr/bin/curl",
                    arguments: [
                        "--http1.1",
                        "-L",
                        "--fail",
                        "--retry", "3",
                        "--retry-delay", "2",
                        "--silent",
                        "--show-error",
                        "--output", pkgURL.path,
                        layout.releasePackageURL.absoluteString,
                    ]
                )
            }

            try runHostTool(executable: "/usr/sbin/pkgutil", arguments: ["--expand-full", pkgURL.path, expandedURL.path])

            let payload = try ExpandedContainerPackage(root: expandedURL)
            try fm.createDirectory(
                at: stagingInstallRoot.appendingPathComponent("bin"),
                withIntermediateDirectories: true
            )
            try fm.createDirectory(
                at: stagingInstallRoot.appendingPathComponent("libexec"),
                withIntermediateDirectories: true
            )

            try copyReplacing(
                from: payload.containerCLI,
                to: stagingInstallRoot.appendingPathComponent("bin/container")
            )
            try copyReplacing(
                from: payload.containerAPIServer,
                to: stagingInstallRoot.appendingPathComponent("bin/container-apiserver")
            )
            try copyReplacing(
                from: payload.libexecContainer,
                to: stagingInstallRoot.appendingPathComponent("libexec/container")
            )

            try fm.createDirectory(at: layout.root, withIntermediateDirectories: true)
            try copyReplacing(from: stagingInstallRoot, to: layout.installRoot)
        } catch let error as ContainerBridgeError {
            throw error
        } catch {
            throw ContainerBridgeError.runtimeBootstrapFailed(error.localizedDescription)
        }
    }

    private func copyReplacing(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: destination)
    }

    private func runHostTool(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCollector = ProcessPipeCollector()
        let stderrCollector = ProcessPipeCollector()
        let outputGroup = DispatchGroup()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        collectOutput(from: stdoutPipe, into: stdoutCollector, group: outputGroup)
        collectOutput(from: stderrPipe, into: stderrCollector, group: outputGroup)
        process.waitUntilExit()
        outputGroup.wait()

        guard process.terminationStatus == 0 else {
            let stdout = String(decoding: stdoutCollector.data(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = String(decoding: stderrCollector.data(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let output = [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            throw ContainerBridgeError.runtimeBootstrapFailed(
                "\(([executable] + arguments).joined(separator: " ")) exited with code \(process.terminationStatus): \(output)"
            )
        }
    }

    private func collectOutput(
        from pipe: Pipe,
        into collector: ProcessPipeCollector,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let handle = pipe.fileHandleForReading
            while true {
                let data = handle.availableData
                if data.isEmpty {
                    break
                }
                collector.append(data)
            }
            group.leave()
        }
    }
}

public struct NoopContainerRuntimeBootstrapper: ContainerRuntimeBootstrapping {
    public init() {}

    public func prepareRuntime(layout: ContainerRuntimeLayout) throws {
        _ = layout
    }
}

private struct ContainerSystemRoots {
    let appRoot: String?
    let installRoot: String?

    init(statusOutput: String) {
        appRoot = Self.value(after: "application data root:", in: statusOutput)
        installRoot = Self.value(after: "application install root:", in: statusOutput)
    }

    func matches(layout: ContainerRuntimeLayout) -> Bool {
        appRoot.map(standardizePath) == standardizePath(layout.appRoot.path)
            && installRoot.map(standardizePath) == standardizePath(layout.installRoot.path)
    }

    private static func value(after prefix: String, in output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { $0.hasPrefix(prefix) }?
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func standardizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

private struct ExpandedContainerPackage {
    let containerCLI: URL
    let containerAPIServer: URL
    let libexecContainer: URL

    init(root: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ContainerBridgeError.runtimeBootstrapFailed("unable to enumerate expanded package at \(root.path)")
        }

        var containerCLI: URL?
        var containerAPIServer: URL?
        var libexecContainer: URL?

        for case let url as URL in enumerator {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            let pathComponents = url.standardizedFileURL.pathComponents
            if resourceValues?.isRegularFile == true {
                if pathComponents.hasSuffix(["usr", "local", "bin", "container"]) || pathComponents.hasSuffix(["bin", "container"]) {
                    containerCLI = url
                } else if pathComponents.hasSuffix(["usr", "local", "bin", "container-apiserver"])
                    || pathComponents.hasSuffix(["bin", "container-apiserver"])
                {
                    containerAPIServer = url
                }
            } else if resourceValues?.isDirectory == true,
                pathComponents.hasSuffix(["usr", "local", "libexec", "container"])
                    || pathComponents.hasSuffix(["libexec", "container"])
            {
                libexecContainer = url
                enumerator.skipDescendants()
            }
        }

        guard let containerCLI, let containerAPIServer, let libexecContainer else {
            throw ContainerBridgeError.runtimeBootstrapFailed("expanded container package is missing required runtime files")
        }
        self.containerCLI = containerCLI
        self.containerAPIServer = containerAPIServer
        self.libexecContainer = libexecContainer
    }
}

private extension Array where Element == String {
    func hasSuffix(_ suffix: [String]) -> Bool {
        guard count >= suffix.count else { return false }
        return Array(self[(count - suffix.count)..<count]) == suffix
    }
}

private final class ProcessPipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        let data = storage
        lock.unlock()
        return data
    }
}

private struct ContainerInspectPayload: Decodable {
    struct Configuration: Decodable {
        struct Image: Decodable {
            let reference: String
        }

        struct Platform: Decodable {
            let os: String?
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
        let platform: Platform?
        let publishedPorts: [PublishedPort]
    }

    let status: String
    let configuration: Configuration
}

private extension ContainerBridgeError {
    var isDarwinPublishUnsupported: Bool {
        guard case let .commandFailed(_, _, stderr) = self else {
            return false
        }

        return stderr.contains("--publish is not supported for --os darwin")
    }

    var isMissingEntrypoint: Bool {
        guard case let .commandFailed(_, _, stderr) = self else {
            return false
        }

        return stderr.contains("command/entrypoint not specified for container process")
    }
}

private extension SandboxDetails {
    init(payload: ContainerInspectPayload) throws {
        if let publishedPort = payload.configuration.publishedPorts.first {
            self.init(
                sandboxID: payload.configuration.id,
                name: payload.configuration.id,
                imageReference: payload.configuration.image.reference,
                publishedHostPort: publishedPort.hostPort,
                agentTransport: .publishedTCP,
                status: .init(containerStatus: payload.status)
            )
            return
        }

        if payload.configuration.platform?.os == "darwin" {
            self.init(
                sandboxID: payload.configuration.id,
                name: payload.configuration.id,
                imageReference: payload.configuration.image.reference,
                publishedHostPort: nil,
                agentTransport: .containerExec,
                status: .init(containerStatus: payload.status)
            )
            return
        }

        throw ContainerBridgeError.publishedPortNotFound(payload.configuration.id)
    }
}
