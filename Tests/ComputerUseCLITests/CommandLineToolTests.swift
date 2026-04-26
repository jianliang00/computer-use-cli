import AgentProtocol
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
func agentCommandsUseMachineHostPortAndProtocolPayloads() throws {
    let homeDirectory = try temporaryDirectory()
    let bridge = StubContainerBridge()
    let agentClient = StubAgentClient()
    let tool = CommandLineTool(
        fileManager: .default,
        homeDirectory: homeDirectory,
        now: { Date(timeIntervalSince1970: 1_710_000_250) },
        containerBridge: bridge,
        agentClient: agentClient
    )

    _ = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "demo",
        "--image", "local/computer-use:authorized",
    ])
    _ = try tool.run(arguments: [
        "machine",
        "start",
        "--machine", "demo",
    ])

    let ping = try tool.run(arguments: [
        "agent",
        "ping",
        "--machine", "demo",
    ])
    #expect(ping.contains("\"version\" : \"0.1.0\""))

    let permissions = try tool.run(arguments: [
        "permissions",
        "get",
        "--machine", "demo",
    ])
    #expect(permissions.contains("\"screen_recording\" : false"))

    let permissionRequest = try tool.run(arguments: [
        "permissions",
        "request",
        "--machine", "demo",
    ])
    #expect(permissionRequest.contains("\"screen_recording\" : false"))

    let apps = try tool.run(arguments: [
        "apps",
        "list",
        "--machine", "demo",
    ])
    #expect(apps.contains("\"bundle_id\" : \"com.apple.TextEdit\""))

    let state = try tool.run(arguments: [
        "state",
        "get",
        "--machine", "demo",
        "--bundle-id", "com.apple.TextEdit",
    ])
    #expect(state.contains("\"snapshot_id\" : \"snap-001\""))
    #expect(agentClient.stateRequests == [StateRequest(bundleID: "com.apple.TextEdit")])

    _ = try tool.run(arguments: [
        "action",
        "click",
        "--machine", "demo",
        "--x", "100",
        "--y", "200",
    ])
    #expect(agentClient.clickRequests == [
        ClickActionRequest(target: .coordinates(Point(x: 100, y: 200)))
    ])

    _ = try tool.run(arguments: [
        "action",
        "type",
        "--machine", "demo",
        "--",
        "hello",
        "world",
    ])
    #expect(agentClient.typeRequests == [TypeActionRequest(text: "hello world")])

    let doctor = try tool.run(arguments: [
        "agent",
        "doctor",
        "--machine", "demo",
    ])
    #expect(doctor.contains("\"bootstrap_ready\" : null"))
    #expect(doctor.contains("\"session_agent_ready\" : true"))

    #expect(agentClient.baseURLs.allSatisfy { $0.absoluteString == "http://127.0.0.1:46000" })
}

@Test
func agentCommandsUseContainerExecURLForDarwinSandboxesWithoutPublishedPorts() throws {
    let homeDirectory = try temporaryDirectory()
    let bridge = ContainerExecSandboxBridge()
    let agentClient = StubAgentClient()
    let tool = CommandLineTool(
        fileManager: .default,
        homeDirectory: homeDirectory,
        now: { Date(timeIntervalSince1970: 1_710_000_275) },
        containerBridge: bridge,
        agentClient: agentClient
    )

    _ = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "demo",
        "--image", "local/computer-use:product",
    ])
    let started = try tool.run(arguments: [
        "machine",
        "start",
        "--machine", "demo",
    ])
    #expect(started.contains("\"agentTransport\" : \"container_exec\""))

    _ = try tool.run(arguments: [
        "agent",
        "ping",
        "--machine", "demo",
    ])

    #expect(agentClient.baseURLs.map(\.absoluteString) == ["container-exec://demo"])
}

@Test
func runtimeInfoReportsProjectOwnedContainerSDKRoot() throws {
    let root = URL(fileURLWithPath: "/tmp/computer-use-runtime-test")
    let layout = ContainerRuntimeLayout(version: "1.2.3", root: root)
    let tool = CommandLineTool(
        containerBridge: StubContainerBridge(),
        containerRuntimeLayout: layout,
        containerRuntimeBootstrapper: NoopContainerRuntimeBootstrapper(),
        runtimeContainerRunner: RecordingContainerCommandRunner()
    )

    let output = try tool.run(arguments: ["runtime", "info"])

    #expect(output.contains("\"version\" : \"1.2.3\""))
    #expect(output.contains("\"root\" : \"/tmp/computer-use-runtime-test\""))
    #expect(output.contains("\"app_root\" : \"/tmp/computer-use-runtime-test/app\""))
    #expect(output.contains("\"install_root\" : \"/tmp/computer-use-runtime-test/install\""))
    #expect(output.contains("\"executable\" : \"/tmp/computer-use-runtime-test/install/bin/container\""))
    #expect(output.contains("\"release_package_url\" : \"https://github.com/jianliang00/container/releases/download/1.2.3/container-installer-unsigned.pkg\""))
    #expect(!output.contains("/usr/local/bin/container"))
}

@Test
func runtimeBootstrapUsesConfiguredBootstrapper() throws {
    let layout = ContainerRuntimeLayout(version: "1.2.3", root: URL(fileURLWithPath: "/tmp/cu-runtime-bootstrap"))
    let bootstrapper = RecordingContainerRuntimeBootstrapper()
    let tool = CommandLineTool(
        containerBridge: StubContainerBridge(),
        containerRuntimeLayout: layout,
        containerRuntimeBootstrapper: bootstrapper,
        runtimeContainerRunner: RecordingContainerCommandRunner()
    )

    let output = try tool.run(arguments: ["runtime", "bootstrap"])

    #expect(output.contains("\"bootstrapped\" : true"))
    #expect(bootstrapper.preparedLayouts == [layout])
}

@Test
func runtimeContainerCommandUsesConfiguredRunner() throws {
    let runner = RecordingContainerCommandRunner(result: CommandExecutionResult(
        exitCode: 0,
        stdout: "images ok",
        stderr: ""
    ))
    let tool = CommandLineTool(
        containerBridge: StubContainerBridge(),
        containerRuntimeBootstrapper: NoopContainerRuntimeBootstrapper(),
        runtimeContainerRunner: runner
    )

    let output = try tool.run(arguments: ["runtime", "container", "--", "image", "list"])

    #expect(output == "images ok")
    #expect(runner.arguments == [["image", "list"]])
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

private final class RecordingContainerRuntimeBootstrapper: ContainerRuntimeBootstrapping, @unchecked Sendable {
    private(set) var preparedLayouts: [ContainerRuntimeLayout] = []

    func prepareRuntime(layout: ContainerRuntimeLayout) throws {
        preparedLayouts.append(layout)
    }
}

private final class RecordingContainerCommandRunner: ContainerCommandRunning, @unchecked Sendable {
    private(set) var arguments: [[String]] = []
    private let result: CommandExecutionResult

    init(result: CommandExecutionResult = CommandExecutionResult(exitCode: 0, stdout: "", stderr: "")) {
        self.result = result
    }

    func run(arguments: [String]) throws -> CommandExecutionResult {
        self.arguments.append(arguments)
        return result
    }
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

private final class StubAgentClient: AgentClienting, @unchecked Sendable {
    private(set) var baseURLs: [URL] = []
    private(set) var stateRequests: [StateRequest] = []
    private(set) var clickRequests: [ClickActionRequest] = []
    private(set) var typeRequests: [TypeActionRequest] = []

    func health(baseURL: URL) throws -> HealthResponse {
        baseURLs.append(baseURL)
        return HealthResponse(ok: true, version: "0.1.0")
    }

    func permissions(baseURL: URL) throws -> PermissionsResponse {
        baseURLs.append(baseURL)
        return PermissionsResponse(accessibility: true, screenRecording: false)
    }

    func requestPermissions(baseURL: URL) throws -> PermissionsResponse {
        baseURLs.append(baseURL)
        return PermissionsResponse(accessibility: true, screenRecording: false)
    }

    func apps(baseURL: URL) throws -> AppsResponse {
        baseURLs.append(baseURL)
        return AppsResponse(apps: [
            RunningApplication(
                bundleID: "com.apple.TextEdit",
                name: "TextEdit",
                pid: 123,
                isFrontmost: true
            ),
        ])
    }

    func state(baseURL: URL, request: StateRequest) throws -> StateResponse {
        baseURLs.append(baseURL)
        stateRequests.append(request)
        return StateResponse(
            snapshotID: "snap-001",
            app: ApplicationDescriptor(bundleID: "com.apple.TextEdit", name: "TextEdit", pid: 123),
            window: nil,
            screenshot: ScreenshotPayload(mimeType: "image/png", base64: "ZmFrZQ=="),
            axTree: AXTree(rootID: "root", nodes: [])
        )
    }

    func click(baseURL: URL, request: ClickActionRequest) throws -> ActionResponse {
        baseURLs.append(baseURL)
        clickRequests.append(request)
        return ActionResponse()
    }

    func type(baseURL: URL, request: TypeActionRequest) throws -> ActionResponse {
        baseURLs.append(baseURL)
        typeRequests.append(request)
        return ActionResponse()
    }

    func key(baseURL: URL, request: KeyActionRequest) throws -> ActionResponse {
        baseURLs.append(baseURL)
        return ActionResponse()
    }

    func drag(baseURL: URL, request: DragActionRequest) throws -> ActionResponse {
        baseURLs.append(baseURL)
        return ActionResponse()
    }

    func scroll(baseURL: URL, request: ScrollActionRequest) throws -> ActionResponse {
        baseURLs.append(baseURL)
        return ActionResponse()
    }

    func setValue(baseURL: URL, request: SetValueActionRequest) throws -> ActionResponse {
        baseURLs.append(baseURL)
        return ActionResponse()
    }

    func perform(baseURL: URL, request: ElementActionRequest) throws -> ActionResponse {
        baseURLs.append(baseURL)
        return ActionResponse()
    }
}

private final class ContainerExecSandboxBridge: ContainerRuntimeBridging, @unchecked Sendable {
    private var states: [String: SandboxDetails.Status] = [:]

    func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails {
        states[configuration.name] = .stopped
        return details(for: configuration.name, status: .stopped)
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
        SandboxLogs(sandboxID: id, entries: [])
    }

    func resolvePublishedHostPort(id: String) throws -> Int {
        throw ContainerBridgeError.publishedPortNotFound(id)
    }

    private func details(for id: String, status: SandboxDetails.Status) -> SandboxDetails {
        SandboxDetails(
            sandboxID: id,
            name: id,
            imageReference: "local/computer-use:product",
            publishedHostPort: nil,
            agentTransport: .containerExec,
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
