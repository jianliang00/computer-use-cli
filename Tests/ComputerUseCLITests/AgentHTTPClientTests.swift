import AgentProtocol
import ComputerUseCLI
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
