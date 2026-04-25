import ContainerBridge
import Foundation
import Testing

@Test
func unavailableBridgeThrowsForInspect() throws {
    let bridge = UnavailableContainerBridge()

    do {
        _ = try bridge.inspectSandbox(id: "sandbox-123")
        Issue.record("expected unavailable bridge to throw")
    } catch let error as ContainerBridgeError {
        #expect(error == .notImplemented("inspectSandbox"))
    }
}

@Test
func containerCLIBridgeParsesInspectPayloadAndLogs() throws {
    let runner = QueueContainerCommandRunner(steps: [
        .success(
            arguments: ["inspect", "demo"],
            result: CommandExecutionResult(
                exitCode: 0,
                stdout: #"[{"status":"running","configuration":{"id":"demo","image":{"reference":"local/computer-use:authorized"},"publishedPorts":[{"containerPort":7777,"hostPort":46042,"hostAddress":"127.0.0.1","proto":"tcp","count":1}]}}]"#,
                stderr: ""
            )
        ),
        .success(
            arguments: ["logs", "demo"],
            result: CommandExecutionResult(
                exitCode: 0,
                stdout: "line one\nline two\n",
                stderr: ""
            )
        ),
        .success(
            arguments: ["inspect", "demo"],
            result: CommandExecutionResult(
                exitCode: 0,
                stdout: #"[{"status":"running","configuration":{"id":"demo","image":{"reference":"local/computer-use:authorized"},"publishedPorts":[{"containerPort":7777,"hostPort":46042,"hostAddress":"127.0.0.1","proto":"tcp","count":1}]}}]"#,
                stderr: ""
            )
        ),
    ])
    let bridge = ContainerCLIBridge(runner: runner)

    let details = try bridge.inspectSandbox(id: "demo")
    #expect(details == SandboxDetails(
        sandboxID: "demo",
        name: "demo",
        imageReference: "local/computer-use:authorized",
        publishedHostPort: 46042,
        status: .running
    ))

    let logs = try bridge.queryLogs(id: "demo")
    #expect(logs.entries == ["line one", "line two"])
    #expect(try bridge.resolvePublishedHostPort(id: "demo") == 46042)
}

@Test
func containerCLIBridgeBuildsExpectedLifecycleCommands() throws {
    let runner = QueueContainerCommandRunner(steps: [
        .success(
            arguments: ["create", "--name", "demo", "--gui", "--publish", "127.0.0.1:46000:7777/tcp", "local/computer-use:authorized"],
            result: CommandExecutionResult(exitCode: 0, stdout: "demo", stderr: "")
        ),
        .success(
            arguments: ["inspect", "demo"],
            result: CommandExecutionResult(
                exitCode: 0,
                stdout: #"[{"status":"stopped","configuration":{"id":"demo","image":{"reference":"local/computer-use:authorized"},"publishedPorts":[{"containerPort":7777,"hostPort":46000,"hostAddress":"127.0.0.1","proto":"tcp","count":1}]}}]"#,
                stderr: ""
            )
        ),
        .success(
            arguments: ["start", "demo"],
            result: CommandExecutionResult(exitCode: 0, stdout: "", stderr: "")
        ),
        .success(
            arguments: ["inspect", "demo"],
            result: CommandExecutionResult(
                exitCode: 0,
                stdout: #"[{"status":"running","configuration":{"id":"demo","image":{"reference":"local/computer-use:authorized"},"publishedPorts":[{"containerPort":7777,"hostPort":46000,"hostAddress":"127.0.0.1","proto":"tcp","count":1}]}}]"#,
                stderr: ""
            )
        ),
        .success(
            arguments: ["stop", "demo"],
            result: CommandExecutionResult(exitCode: 0, stdout: "", stderr: "")
        ),
        .success(
            arguments: ["inspect", "demo"],
            result: CommandExecutionResult(
                exitCode: 0,
                stdout: #"[{"status":"stopped","configuration":{"id":"demo","image":{"reference":"local/computer-use:authorized"},"publishedPorts":[{"containerPort":7777,"hostPort":46000,"hostAddress":"127.0.0.1","proto":"tcp","count":1}]}}]"#,
                stderr: ""
            )
        ),
        .success(
            arguments: ["delete", "--force", "demo"],
            result: CommandExecutionResult(exitCode: 0, stdout: "", stderr: "")
        ),
    ])
    let bridge = ContainerCLIBridge(runner: runner)

    let created = try bridge.createSandbox(configuration: SandboxConfiguration(
        name: "demo",
        imageReference: "local/computer-use:authorized",
        publishedHostPort: 46000
    ))
    #expect(created.status == .stopped)

    let started = try bridge.startSandbox(id: "demo")
    #expect(started.status == .running)

    let stopped = try bridge.stopSandbox(id: "demo")
    #expect(stopped.status == .stopped)

    try bridge.removeSandbox(id: "demo")
    #expect(runner.isExhausted)
}

@Test
func containerCLIBridgeAppendsInitArgumentsAfterImage() throws {
    let runner = QueueContainerCommandRunner(steps: [
        .success(
            arguments: [
                "create",
                "--name", "demo",
                "--gui",
                "--publish", "127.0.0.1:46000:7777/tcp",
                "ghcr.io/jianliang00/macos-base:26.3",
                "tail", "-f", "/dev/null",
            ],
            result: CommandExecutionResult(exitCode: 0, stdout: "demo", stderr: "")
        ),
        .success(
            arguments: ["inspect", "demo"],
            result: CommandExecutionResult(
                exitCode: 0,
                stdout: #"[{"status":"stopped","configuration":{"id":"demo","image":{"reference":"ghcr.io/jianliang00/macos-base:26.3"},"publishedPorts":[{"containerPort":7777,"hostPort":46000,"hostAddress":"127.0.0.1","proto":"tcp","count":1}]}}]"#,
                stderr: ""
            )
        ),
    ])
    let bridge = ContainerCLIBridge(runner: runner)

    let created = try bridge.createSandbox(configuration: SandboxConfiguration(
        name: "demo",
        imageReference: "ghcr.io/jianliang00/macos-base:26.3",
        publishedHostPort: 46000,
        initProcessArguments: ["tail", "-f", "/dev/null"]
    ))

    #expect(created.imageReference == "ghcr.io/jianliang00/macos-base:26.3")
    #expect(runner.isExhausted)
}

@Test
func containerCLIBridgeFallsBackWhenDarwinPublishIsUnsupported() throws {
    let runner = QueueContainerCommandRunner(steps: [
        .failure(
            arguments: ["create", "--name", "demo", "--gui", "--publish", "127.0.0.1:46000:7777/tcp", "local/computer-use:product"],
            error: ContainerBridgeError.commandFailed(
                command: ["container", "create"],
                exitCode: 1,
                stderr: #"unsupported: "--publish is not supported for --os darwin""#
            )
        ),
        .success(
            arguments: ["create", "--name", "demo", "--gui", "local/computer-use:product"],
            result: CommandExecutionResult(exitCode: 0, stdout: "demo", stderr: "")
        ),
        .success(
            arguments: ["inspect", "demo"],
            result: CommandExecutionResult(
                exitCode: 0,
                stdout: #"[{"status":"stopped","configuration":{"id":"demo","platform":{"os":"darwin","architecture":"arm64"},"image":{"reference":"local/computer-use:product"},"publishedPorts":[]}}]"#,
                stderr: ""
            )
        ),
    ])
    let bridge = ContainerCLIBridge(runner: runner)

    let details = try bridge.createSandbox(configuration: SandboxConfiguration(
        name: "demo",
        imageReference: "local/computer-use:product",
        publishedHostPort: 46000
    ))

    #expect(details.publishedHostPort == nil)
    #expect(details.agentTransport == .containerExec)
    #expect(runner.isExhausted)
}

@Test
func processContainerCommandRunnerDrainsLargeStdoutWhileProcessRuns() throws {
    let runner = ProcessContainerCommandRunner(executableURL: URL(fileURLWithPath: "/usr/bin/perl"))
    let result = try runner.run(arguments: ["-e", #"print "x" x 2097152"#])

    #expect(result.stdout.count == 2_097_152)
    #expect(result.stderr.isEmpty)
}

private final class QueueContainerCommandRunner: ContainerCommandRunning, @unchecked Sendable {
    struct Step {
        let arguments: [String]
        let result: Result<CommandExecutionResult, Error>

        static func success(arguments: [String], result: CommandExecutionResult) -> Step {
            Step(arguments: arguments, result: .success(result))
        }

        static func failure(arguments: [String], error: Error) -> Step {
            Step(arguments: arguments, result: .failure(error))
        }
    }

    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    var isExhausted: Bool {
        steps.isEmpty
    }

    func run(arguments: [String]) throws -> CommandExecutionResult {
        guard steps.isEmpty == false else {
            throw ContainerBridgeError.commandFailed(
                command: arguments,
                exitCode: 127,
                stderr: "no more stubbed commands"
            )
        }

        let next = steps.removeFirst()
        #expect(next.arguments == arguments)
        return try next.result.get()
    }
}
