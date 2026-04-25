import AgentProtocol
import ComputerUseCLI
import ContainerBridge
import Foundation
import Testing

@Test
func agentHTTPClientBuildsExpectedRequests() throws {
    let transport = QueueAgentHTTPTransport(steps: [
        .init(
            method: "GET",
            path: "/health",
            body: nil,
            response: AgentHTTPTransportResponse(
                statusCode: 200,
                body: try AgentProtocolJSON.encode(HealthResponse(ok: true, version: "0.1.0"))
            )
        ),
        .init(
            method: "POST",
            path: "/permissions/request",
            body: #"{}"#,
            response: AgentHTTPTransportResponse(
                statusCode: 200,
                body: try AgentProtocolJSON.encode(PermissionsResponse(
                    accessibility: false,
                    screenRecording: false
                ))
            )
        ),
        .init(
            method: "POST",
            path: "/state",
            body: #"{"bundle_id":"com.apple.TextEdit"}"#,
            response: AgentHTTPTransportResponse(
                statusCode: 200,
                body: try AgentProtocolJSON.encode(StateResponse(
                    snapshotID: "snap-001",
                    app: ApplicationDescriptor(bundleID: "com.apple.TextEdit", name: "TextEdit", pid: 123),
                    window: nil,
                    screenshot: ScreenshotPayload(mimeType: "image/png", base64: "ZmFrZQ=="),
                    axTree: AXTree(rootID: "root", nodes: [])
                ))
            )
        ),
    ])
    let client = AgentHTTPClient(transport: transport)
    let baseURL = try #require(URL(string: "http://127.0.0.1:46000"))

    let health = try client.health(baseURL: baseURL)
    #expect(health == HealthResponse(ok: true, version: "0.1.0"))

    let permissions = try client.requestPermissions(baseURL: baseURL)
    #expect(permissions == PermissionsResponse(accessibility: false, screenRecording: false))

    let state = try client.state(
        baseURL: baseURL,
        request: StateRequest(bundleID: "com.apple.TextEdit")
    )
    #expect(state.snapshotID == "snap-001")
    #expect(transport.isExhausted)
}

@Test
func agentHTTPClientDecodesProtocolErrors() throws {
    let transport = QueueAgentHTTPTransport(steps: [
        .init(
            method: "GET",
            path: "/permissions",
            body: nil,
            response: AgentHTTPTransportResponse(
                statusCode: 403,
                body: try AgentProtocolJSON.encode(ErrorResponse(
                    error: AgentError(
                        code: .permissionDenied,
                        message: "Screen Recording is not granted"
                    )
                ))
            )
        ),
    ])
    let client = AgentHTTPClient(transport: transport)
    let baseURL = try #require(URL(string: "http://127.0.0.1:46000"))

    do {
        _ = try client.permissions(baseURL: baseURL)
        Issue.record("expected protocol error")
    } catch let error as AgentClientError {
        #expect(error == .agentError(
            statusCode: 403,
            error: AgentError(
                code: .permissionDenied,
                message: "Screen Recording is not granted"
            )
        ))
    }
}

@Test
func containerExecTransportRunsCurlInsideSandbox() throws {
    let runner = RecordingContainerCommandRunner(result: CommandExecutionResult(
        exitCode: 0,
        stdout: #"{"ok":true,"version":"0.1.0"}"# + "\n__CU_HTTP_STATUS__:200\n",
        stderr: ""
    ))
    let transport = ContainerExecAgentHTTPTransport(runner: runner)
    let request = URLRequest(url: try #require(URL(string: "container-exec://demo/health")))

    let response = try transport.send(request)

    #expect(response.statusCode == 200)
    #expect(String(decoding: response.body, as: UTF8.self) == #"{"ok":true,"version":"0.1.0"}"#)
    #expect(runner.arguments == [
        "exec", "demo",
        "/usr/bin/curl",
        "-sS",
        "--max-time", "30",
        "-w", "\n__CU_HTTP_STATUS__:%{http_code}\n",
        "-X", "GET",
        "http://127.0.0.1:7777/health",
    ])
}

@Test
func containerExecTransportSendsPostBodyThroughBase64() throws {
    let runner = RecordingContainerCommandRunner(result: CommandExecutionResult(
        exitCode: 0,
        stdout: #"{"ok":true}"# + "\n__CU_HTTP_STATUS__:200\n",
        stderr: ""
    ))
    let transport = ContainerExecAgentHTTPTransport(runner: runner)
    var request = URLRequest(url: try #require(URL(string: "container-exec://demo/actions/type")))
    request.httpMethod = "POST"
    request.httpBody = Data(#"{"text":"hello"}"#.utf8)

    _ = try transport.send(request)

    #expect(Array(runner.arguments.prefix(4)) == [
        "exec", "demo",
        "/bin/sh", "-c",
    ])
    #expect(runner.arguments[4].contains("/usr/bin/base64 -D"))
    #expect(Array(runner.arguments.suffix(3)) == [
        #"eyJ0ZXh0IjoiaGVsbG8ifQ=="#,
        "POST",
        "http://127.0.0.1:7777/actions/type",
    ])
}

private final class QueueAgentHTTPTransport: AgentHTTPTransporting, @unchecked Sendable {
    struct Step {
        let method: String
        let path: String
        let body: String?
        let response: AgentHTTPTransportResponse
    }

    private var steps: [Step]

    init(steps: [Step]) {
        self.steps = steps
    }

    var isExhausted: Bool {
        steps.isEmpty
    }

    func send(_ request: URLRequest) throws -> AgentHTTPTransportResponse {
        let step = steps.removeFirst()
        #expect(request.httpMethod == step.method)
        #expect(request.url?.path == step.path)

        if let expectedBody = step.body {
            let actualBody = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            #expect(actualBody == expectedBody)
        } else {
            #expect(request.httpBody == nil)
        }

        return step.response
    }
}

private final class RecordingContainerCommandRunner: ContainerCommandRunning, @unchecked Sendable {
    private let result: CommandExecutionResult
    private(set) var arguments: [String] = []

    init(result: CommandExecutionResult) {
        self.result = result
    }

    func run(arguments: [String]) throws -> CommandExecutionResult {
        self.arguments = arguments
        return result
    }
}
