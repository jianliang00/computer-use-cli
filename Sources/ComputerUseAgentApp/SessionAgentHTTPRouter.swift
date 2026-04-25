import AgentProtocol
import ComputerUseAgentCore
import Foundation

public struct SessionAgentHTTPRequest: Equatable, Sendable {
    public enum Method: String, Equatable, Sendable {
        case get = "GET"
        case post = "POST"
    }

    public var method: Method
    public var path: String
    public var body: Data

    public init(method: Method, path: String, body: Data = Data()) {
        self.method = method
        self.path = path
        self.body = body
    }
}

public struct SessionAgentHTTPResponse: Equatable, Sendable {
    public var statusCode: Int
    public var headers: [String: String]
    public var body: Data

    public init(
        statusCode: Int,
        headers: [String: String] = [:],
        body: Data = Data()
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public final class SessionAgentHTTPRouter: Sendable {
    private let configuration: SessionAgentConfiguration
    private let agent: any ComputerUseSessionAgent

    public init(
        configuration: SessionAgentConfiguration = .guestDefault,
        agent: any ComputerUseSessionAgent
    ) {
        self.configuration = configuration
        self.agent = agent
    }

    public func handle(_ request: SessionAgentHTTPRequest) async -> SessionAgentHTTPResponse {
        do {
            switch (request.method, request.path) {
            case (.get, "/health"):
                return try json(HealthResponse(ok: true, version: "0.1.0"))
            case (.get, "/permissions"):
                return try await permissions()
            case (.post, "/permissions/request"):
                return try await requestPermissions()
            case (.get, "/apps"):
                return try await apps()
            case (.post, "/state"):
                try await requireAutomationPermissions()
                return try await state(request)
            case (.post, "/actions/click"):
                try await requireAutomationPermissions()
                return try await click(request)
            case (.post, "/actions/type"):
                try await requireAutomationPermissions()
                return try await type(request)
            case (.post, "/actions/key"):
                try await requireAutomationPermissions()
                return try await key(request)
            case (.post, "/actions/drag"):
                try await requireAutomationPermissions()
                return try await drag(request)
            case (.post, "/actions/scroll"):
                try await requireAutomationPermissions()
                return try await scroll(request)
            case (.post, "/actions/set-value"):
                try await requireAutomationPermissions()
                return try await setValue(request)
            case (.post, "/actions/action"):
                try await requireAutomationPermissions()
                return try await perform(request)
            default:
                return try error(
                    statusCode: 404,
                    code: .invalidRequest,
                    message: "No route for \(request.method.rawValue) \(request.path)"
                )
            }
        } catch let routeError as SessionAgentHTTPRouteError {
            return routeError.response()
        } catch let cacheError as SnapshotCacheError {
            return snapshotCacheError(cacheError)
        } catch let coreError as ComputerUseAgentCoreError {
            return unsupported(coreError.localizedDescription)
        } catch let decodingError as DecodingError {
            return invalidRequest(String(describing: decodingError))
        } catch {
            return invalidRequest(error.localizedDescription)
        }
    }

    private func permissions() async throws -> SessionAgentHTTPResponse {
        let snapshot = try await agent.currentPermissions()
        return try json(PermissionsResponse(
            accessibility: snapshot.accessibility == .authorized,
            screenRecording: snapshot.screenRecording == .authorized
        ))
    }

    private func requestPermissions() async throws -> SessionAgentHTTPResponse {
        let snapshot = try await agent.requestPermissions()
        return try json(PermissionsResponse(
            accessibility: snapshot.accessibility == .authorized,
            screenRecording: snapshot.screenRecording == .authorized
        ))
    }

    private func apps() async throws -> SessionAgentHTTPResponse {
        let applications = try await agent.runningApplications()
        return try json(AppsResponse(
            apps: applications.map { application in
                AgentProtocol.RunningApplication(
                    bundleID: application.bundleIdentifier,
                    name: application.name,
                    pid: Int(application.processIdentifier),
                    isFrontmost: application.isFrontmost
                )
            }
        ))
    }

    private func state(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let stateRequest = try decode(StateRequest.self, from: request)
        let snapshot = try await agent.captureState(bundleIdentifier: stateRequest.bundleID)
        let app = selectedApplication(
            applications: snapshot.applications,
            bundleID: stateRequest.bundleID
        )
        guard let app else {
            throw SessionAgentHTTPRouteError.agent(
                statusCode: 404,
                code: .appNotFound,
                message: stateRequest.bundleID.map { "Application \($0) was not found" }
                    ?? "No running application is available"
            )
        }

        return try json(StateResponse(
            snapshotID: snapshot.snapshotID,
            app: ApplicationDescriptor(
                bundleID: app.bundleIdentifier,
                name: app.name,
                pid: Int(app.processIdentifier)
            ),
            window: nil,
            screenshot: ScreenshotPayload(
                mimeType: "image/png",
                base64: Data(snapshot.screenshot.bytes).base64EncodedString()
            ),
            axTree: AXTree(rootID: snapshot.accessibilityRoot.id, nodes: flatten(snapshot.accessibilityRoot))
        ))
    }

    private func click(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.ClickActionRequest.self, from: request)
        switch action.target {
        case let .coordinates(point):
            _ = try await agent.click(ComputerUseAgentCore.ClickActionRequest(
                location: ComputerUseAgentCore.Point(x: point.x, y: point.y),
                button: ComputerUseAgentCore.MouseButton(rawValue: action.button.rawValue) ?? .left,
                clickCount: action.clickCount
            ))
            return try json(ActionResponse())
        case let .element(reference):
            _ = try await agent.click(ComputerUseAgentCore.ClickActionRequest(
                snapshotID: reference.snapshotID,
                elementID: reference.elementID,
                button: ComputerUseAgentCore.MouseButton(rawValue: action.button.rawValue) ?? .left,
                clickCount: action.clickCount
            ))
            return try json(ActionResponse())
        }
    }

    private func type(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.TypeActionRequest.self, from: request)
        _ = try await agent.type(ComputerUseAgentCore.TypeActionRequest(text: action.text))
        return try json(ActionResponse())
    }

    private func key(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.KeyActionRequest.self, from: request)
        _ = try await agent.key(ComputerUseAgentCore.KeyActionRequest(key: action.key))
        return try json(ActionResponse())
    }

    private func drag(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.DragActionRequest.self, from: request)
        _ = try await agent.drag(ComputerUseAgentCore.DragActionRequest(
            start: ComputerUseAgentCore.Point(x: action.from.x, y: action.from.y),
            end: ComputerUseAgentCore.Point(x: action.to.x, y: action.to.y)
        ))
        return try json(ActionResponse())
    }

    private func scroll(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.ScrollActionRequest.self, from: request)
        let delta = scrollDelta(direction: action.direction, pages: action.pages)
        _ = try await agent.scroll(ComputerUseAgentCore.ScrollActionRequest(
            deltaX: delta.x,
            deltaY: delta.y
        ))
        return try json(ActionResponse())
    }

    private func setValue(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.SetValueActionRequest.self, from: request)
        _ = try await agent.setValue(ComputerUseAgentCore.SetValueActionRequest(
            elementID: action.target.elementID,
            value: action.value,
            snapshotID: action.target.snapshotID
        ))
        return try json(ActionResponse())
    }

    private func perform(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.ElementActionRequest.self, from: request)
        _ = try await agent.perform(ComputerUseAgentCore.ElementActionRequest(
            elementID: action.target.elementID,
            actionName: action.name,
            snapshotID: action.target.snapshotID
        ))
        return try json(ActionResponse())
    }

    private func requireAutomationPermissions() async throws {
        let permissions = try await agent.currentPermissions()
        guard permissions.isReadyForAutomation else {
            let missing = permissions.missingPermissions.map(\.rawValue).joined(separator: ", ")
            throw SessionAgentHTTPRouteError.agent(
                statusCode: 403,
                code: .permissionDenied,
                message: "Missing permissions: \(missing)"
            )
        }
    }

    private func selectedApplication(
        applications: [ComputerUseAgentCore.RunningApplication],
        bundleID: String?
    ) -> ComputerUseAgentCore.RunningApplication? {
        if let bundleID {
            return applications.first { $0.bundleIdentifier == bundleID }
        }

        return applications.first { $0.isFrontmost } ?? applications.first
    }

    private func flatten(_ root: AccessibilityNode) -> [AXNode] {
        var nodes: [AXNode] = []

        func walk(_ node: AccessibilityNode) {
            nodes.append(AXNode(
                id: node.id,
                role: node.role,
                title: node.title,
                value: node.value,
                bounds: node.frame.map(protocolRect),
                children: node.children.map(\.id),
                actions: []
            ))

            node.children.forEach(walk)
        }

        walk(root)
        return nodes
    }

    private func protocolRect(_ rect: ComputerUseAgentCore.Rect) -> AgentProtocol.Rect {
        AgentProtocol.Rect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    private func scrollDelta(direction: ScrollDirection, pages: Int) -> (x: Double, y: Double) {
        let amount = Double(max(pages, 1)) * 800

        switch direction {
        case .up:
            return (0, amount)
        case .down:
            return (0, -amount)
        case .left:
            return (amount, 0)
        case .right:
            return (-amount, 0)
        }
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from request: SessionAgentHTTPRequest
    ) throws -> Value {
        try AgentProtocolJSON.decode(type, from: request.body)
    }

    private func json<Value: Encodable>(
        _ value: Value,
        statusCode: Int = 200
    ) throws -> SessionAgentHTTPResponse {
        SessionAgentHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: try AgentProtocolJSON.encode(value)
        )
    }

    private func invalidRequest(_ message: String) -> SessionAgentHTTPResponse {
        do {
            return try error(statusCode: 400, code: .invalidRequest, message: message)
        } catch {
            return SessionAgentHTTPResponse(statusCode: 500)
        }
    }

    private func unsupported(_ message: String) -> SessionAgentHTTPResponse {
        do {
            return try error(statusCode: 501, code: .unsupportedAction, message: message)
        } catch {
            return SessionAgentHTTPResponse(statusCode: 500)
        }
    }

    private func snapshotCacheError(_ error: SnapshotCacheError) -> SessionAgentHTTPResponse {
        do {
            switch error {
            case let .snapshotExpired(snapshotID):
                return try self.error(
                    statusCode: 410,
                    code: .snapshotExpired,
                    message: snapshotID.isEmpty
                        ? "Snapshot id is required"
                        : "Snapshot \(snapshotID) has expired"
                )
            case let .elementNotFound(snapshotID, elementID):
                return try self.error(
                    statusCode: 404,
                    code: .elementNotFound,
                    message: "Element \(elementID) was not found in snapshot \(snapshotID)"
                )
            }
        } catch {
            return SessionAgentHTTPResponse(statusCode: 500)
        }
    }

    private func error(
        statusCode: Int,
        code: AgentErrorCode,
        message: String
    ) throws -> SessionAgentHTTPResponse {
        try json(
            ErrorResponse(error: AgentError(code: code, message: message)),
            statusCode: statusCode
        )
    }
}

private enum SessionAgentHTTPRouteError: Error {
    case agent(statusCode: Int, code: AgentErrorCode, message: String)

    func response() -> SessionAgentHTTPResponse {
        switch self {
        case let .agent(statusCode, code, message):
            let body = (try? AgentProtocolJSON.encode(ErrorResponse(
                error: AgentError(code: code, message: message)
            ))) ?? Data()
            return SessionAgentHTTPResponse(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                body: body
            )
        }
    }
}
