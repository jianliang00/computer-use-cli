import AgentProtocol
import Foundation

public protocol AgentClienting: Sendable {
    func health(baseURL: URL) throws -> HealthResponse
    func permissions(baseURL: URL) throws -> PermissionsResponse
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

    public init(transport: any AgentHTTPTransporting = URLSessionAgentHTTPTransport()) {
        self.transport = transport
    }

    public func health(baseURL: URL) throws -> HealthResponse {
        try get("/health", baseURL: baseURL)
    }

    public func permissions(baseURL: URL) throws -> PermissionsResponse {
        try get("/permissions", baseURL: baseURL)
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
