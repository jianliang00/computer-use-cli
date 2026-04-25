import AgentProtocol
import ContainerBridge
import Foundation

public protocol AgentClienting: Sendable {
    func health(baseURL: URL) throws -> HealthResponse
    func permissions(baseURL: URL) throws -> PermissionsResponse
    func requestPermissions(baseURL: URL) throws -> PermissionsResponse
    func apps(baseURL: URL) throws -> AppsResponse
    func state(baseURL: URL, request: StateRequest) throws -> StateResponse
    func click(baseURL: URL, request: ClickActionRequest) throws -> ActionResponse
    func type(baseURL: URL, request: TypeActionRequest) throws -> ActionResponse
    func key(baseURL: URL, request: KeyActionRequest) throws -> ActionResponse
    func drag(baseURL: URL, request: DragActionRequest) throws -> ActionResponse
    func scroll(baseURL: URL, request: ScrollActionRequest) throws -> ActionResponse
    func setValue(baseURL: URL, request: SetValueActionRequest) throws -> ActionResponse
    func perform(baseURL: URL, request: ElementActionRequest) throws -> ActionResponse
}

public struct AgentHTTPClient: AgentClienting {
    private let transport: any AgentHTTPTransporting

    public init(transport: any AgentHTTPTransporting = DefaultAgentHTTPTransport()) {
        self.transport = transport
    }

    public func health(baseURL: URL) throws -> HealthResponse {
        try get("/health", baseURL: baseURL)
    }

    public func permissions(baseURL: URL) throws -> PermissionsResponse {
        try get("/permissions", baseURL: baseURL)
    }

    public func requestPermissions(baseURL: URL) throws -> PermissionsResponse {
        try post("/permissions/request", baseURL: baseURL, body: EmptyRequestBody())
    }

    public func apps(baseURL: URL) throws -> AppsResponse {
        try get("/apps", baseURL: baseURL)
    }

    public func state(baseURL: URL, request: StateRequest) throws -> StateResponse {
        try post("/state", baseURL: baseURL, body: request)
    }

    public func click(baseURL: URL, request: ClickActionRequest) throws -> ActionResponse {
        try post("/actions/click", baseURL: baseURL, body: request)
    }

    public func type(baseURL: URL, request: TypeActionRequest) throws -> ActionResponse {
        try post("/actions/type", baseURL: baseURL, body: request)
    }

    public func key(baseURL: URL, request: KeyActionRequest) throws -> ActionResponse {
        try post("/actions/key", baseURL: baseURL, body: request)
    }

    public func drag(baseURL: URL, request: DragActionRequest) throws -> ActionResponse {
        try post("/actions/drag", baseURL: baseURL, body: request)
    }

    public func scroll(baseURL: URL, request: ScrollActionRequest) throws -> ActionResponse {
        try post("/actions/scroll", baseURL: baseURL, body: request)
    }

    public func setValue(baseURL: URL, request: SetValueActionRequest) throws -> ActionResponse {
        try post("/actions/set-value", baseURL: baseURL, body: request)
    }

    public func perform(baseURL: URL, request: ElementActionRequest) throws -> ActionResponse {
        try post("/actions/action", baseURL: baseURL, body: request)
    }

    private func get<Response: Decodable>(_ path: String, baseURL: URL) throws -> Response {
        var request = URLRequest(url: endpoint(baseURL: baseURL, path: path))
        request.httpMethod = "GET"
        return try send(request)
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        baseURL: URL,
        body: Body
    ) throws -> Response {
        var request = URLRequest(url: endpoint(baseURL: baseURL, path: path))
        request.httpMethod = "POST"
        request.httpBody = try AgentProtocolJSON.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try send(request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) throws -> Response {
        let response = try transport.send(request)

        guard (200..<300).contains(response.statusCode) else {
            if let errorResponse = try? AgentProtocolJSON.decode(ErrorResponse.self, from: response.body) {
                throw AgentClientError.agentError(
                    statusCode: response.statusCode,
                    error: errorResponse.error
                )
            }

            let body = String(decoding: response.body, as: UTF8.self)
            throw AgentClientError.httpFailure(statusCode: response.statusCode, body: body)
        }

        return try AgentProtocolJSON.decode(Response.self, from: response.body)
    }

    private func endpoint(baseURL: URL, path: String) -> URL {
        var url = baseURL
        for component in path.split(separator: "/") {
            url.append(path: String(component))
        }
        return url
    }
}

private struct EmptyRequestBody: Encodable {}

public struct AgentHTTPTransportResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol AgentHTTPTransporting: Sendable {
    func send(_ request: URLRequest) throws -> AgentHTTPTransportResponse
}

public struct DefaultAgentHTTPTransport: AgentHTTPTransporting {
    private let urlSessionTransport: any AgentHTTPTransporting
    private let containerExecTransport: any AgentHTTPTransporting

    public init(
        urlSessionTransport: any AgentHTTPTransporting = URLSessionAgentHTTPTransport(),
        containerExecTransport: any AgentHTTPTransporting = ContainerExecAgentHTTPTransport()
    ) {
        self.urlSessionTransport = urlSessionTransport
        self.containerExecTransport = containerExecTransport
    }

    public func send(_ request: URLRequest) throws -> AgentHTTPTransportResponse {
        if request.url?.scheme == "container-exec" {
            return try containerExecTransport.send(request)
        }

        return try urlSessionTransport.send(request)
    }
}

public struct URLSessionAgentHTTPTransport: AgentHTTPTransporting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) throws -> AgentHTTPTransportResponse {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedAgentHTTPResult()

        let task = session.dataTask(with: request) { data, response, error in
            let completion: Result<AgentHTTPTransportResponse, Error>
            if let error {
                completion = .failure(error)
            } else if let httpResponse = response as? HTTPURLResponse {
                completion = .success(AgentHTTPTransportResponse(
                    statusCode: httpResponse.statusCode,
                    body: data ?? Data()
                ))
            } else {
                completion = .failure(AgentClientError.invalidHTTPResponse)
            }

            resultBox.set(completion)
            semaphore.signal()
        }

        task.resume()
        semaphore.wait()

        let completed = resultBox.get()
        guard let completed else {
            throw AgentClientError.invalidHTTPResponse
        }

        return try completed.get()
    }
}

public struct ContainerExecAgentHTTPTransport: AgentHTTPTransporting {
    private static let statusMarker = "__CU_HTTP_STATUS__:"

    private let runner: any ContainerCommandRunning
    private let agentPort: Int
    private let timeoutSeconds: Int

    public init(
        runner: any ContainerCommandRunning = ProcessContainerCommandRunner(),
        agentPort: Int = 7777,
        timeoutSeconds: Int = 30
    ) {
        self.runner = runner
        self.agentPort = agentPort
        self.timeoutSeconds = timeoutSeconds
    }

    public func send(_ request: URLRequest) throws -> AgentHTTPTransportResponse {
        guard let url = request.url,
              url.scheme == "container-exec",
              let sandboxID = url.host,
              sandboxID.isEmpty == false
        else {
            throw AgentClientError.invalidHTTPResponse
        }

        let result = try runner.run(arguments: curlArguments(
            sandboxID: sandboxID,
            request: request,
            agentURL: agentURL(for: url)
        ))

        return try parseCurlOutput(result.stdout)
    }

    private func curlArguments(
        sandboxID: String,
        request: URLRequest,
        agentURL: String
    ) -> [String] {
        let method = request.httpMethod ?? "GET"
        guard let body = request.httpBody, body.isEmpty == false else {
            return [
                "exec", sandboxID,
                "/usr/bin/curl",
                "-sS",
                "--max-time", "\(timeoutSeconds)",
                "-w", "\n\(Self.statusMarker)%{http_code}\n",
                "-X", method,
                agentURL,
            ]
        }

        let encodedBody = body.base64EncodedString()
        let script = """
        set -e
        body_file="/tmp/computer-use-agent-request-$$.json"
        trap 'rm -f "$body_file"' EXIT
        printf "%s" "$1" | /usr/bin/base64 -D > "$body_file"
        /usr/bin/curl -sS --max-time "\(timeoutSeconds)" -w "\\n\(Self.statusMarker)%{http_code}\\n" -X "$2" -H "Content-Type: application/json" --data-binary "@$body_file" "$3"
        """

        return [
            "exec", sandboxID,
            "/bin/sh", "-c", script,
            "sh",
            encodedBody,
            method,
            agentURL,
        ]
    }

    private func agentURL(for url: URL) -> String {
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, query.isEmpty == false {
            path += "?\(query)"
        }

        return "http://127.0.0.1:\(agentPort)\(path)"
    }

    private func parseCurlOutput(_ stdout: String) throws -> AgentHTTPTransportResponse {
        guard let markerRange = stdout.range(
            of: "\n\(Self.statusMarker)",
            options: .backwards
        ) else {
            throw AgentClientError.invalidHTTPResponse
        }

        let body = stdout[..<markerRange.lowerBound]
        let statusText = stdout[markerRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let statusCode = Int(statusText) else {
            throw AgentClientError.invalidHTTPResponse
        }

        return AgentHTTPTransportResponse(
            statusCode: statusCode,
            body: Data(String(body).utf8)
        )
    }
}

private final class LockedAgentHTTPResult: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<AgentHTTPTransportResponse, Error>?

    func set(_ result: Result<AgentHTTPTransportResponse, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func get() -> Result<AgentHTTPTransportResponse, Error>? {
        lock.lock()
        let result = self.result
        lock.unlock()
        return result
    }
}

public enum AgentClientError: Error, LocalizedError, Equatable {
    case invalidHTTPResponse
    case httpFailure(statusCode: Int, body: String)
    case agentError(statusCode: Int, error: AgentError)

    public var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            "agent returned a non-HTTP response"
        case let .httpFailure(statusCode, body):
            body.isEmpty
                ? "agent request failed with HTTP \(statusCode)"
                : "agent request failed with HTTP \(statusCode): \(body)"
        case let .agentError(statusCode, error):
            "agent request failed with HTTP \(statusCode): \(error.code.rawValue): \(error.message)"
        }
    }
}
