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
            case (.post, "/apps/activate"):
                return try await activateApp(request)
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
        } catch let activationError as ApplicationActivationError {
            return appActivationError(activationError)
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
                    isFrontmost: application.isFrontmost,
                    isRunning: application.isRunning,
                    lastUsed: application.lastUsed.map(formatDate),
                    uses: application.useCount
                )
            }
        ))
    }

    private func activateApp(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let activationRequest = try decode(AppActivationRequest.self, from: request)
        let application = try await agent.activateApplication(target: activationRequest.app)
        return try json(AppActivationResponse(app: appDescriptor(application)))
    }

    private func state(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let stateRequest = try decode(StateRequest.self, from: request)
        let bundleID = try await stateTargetBundleID(stateRequest)
        let snapshot = try await agent.captureState(bundleIdentifier: bundleID)
        let app = selectedApplication(
            applications: snapshot.applications,
            bundleID: bundleID
        )
        guard let app else {
            throw SessionAgentHTTPRouteError.agent(
                statusCode: 404,
                code: .appNotFound,
                message: (stateRequest.app ?? stateRequest.bundleID).map { "Application \($0) was not found" }
                    ?? "No running application is available"
            )
        }

        let axNodes = flatten(snapshot.accessibilityRoot)
        let focusedElement = snapshot.focusedElementID.flatMap { focusedElementID in
            axNodes.first { $0.id == focusedElementID }
        }

        return try json(StateResponse(
            snapshotID: snapshot.snapshotID,
            app: appDescriptor(app),
            window: nil,
            screenshot: ScreenshotPayload(
                mimeType: "image/png",
                base64: Data(snapshot.screenshot.bytes).base64EncodedString()
            ),
            axTree: AXTree(rootID: snapshot.accessibilityRoot.id, nodes: axNodes),
            axTreeText: readableAXTree(root: snapshot.accessibilityRoot),
            focusedElement: focusedElement
        ))
    }

    private func click(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.ClickActionRequest.self, from: request)
        let appBundleIdentifier = try await activateAppIfRequested(action.app)
        switch action.target {
        case let .coordinates(point):
            _ = try await agent.click(ComputerUseAgentCore.ClickActionRequest(
                location: ComputerUseAgentCore.Point(x: point.x, y: point.y),
                button: ComputerUseAgentCore.MouseButton(rawValue: action.button.rawValue) ?? .left,
                clickCount: action.clickCount
            ))
            return try json(ActionResponse())
        case let .element(reference):
            let button = ComputerUseAgentCore.MouseButton(rawValue: action.button.rawValue) ?? .left
            let request: ComputerUseAgentCore.ClickActionRequest
            if let elementIndex = reference.elementIndex {
                request = ComputerUseAgentCore.ClickActionRequest(
                    snapshotID: reference.snapshotID,
                    elementIndex: elementIndex,
                    button: button,
                    clickCount: action.clickCount,
                    appBundleIdentifier: appBundleIdentifier
                )
            } else {
                request = ComputerUseAgentCore.ClickActionRequest(
                    snapshotID: try requiredSnapshotID(reference),
                    elementID: try requiredElementID(reference),
                    button: button,
                    clickCount: action.clickCount,
                    appBundleIdentifier: appBundleIdentifier
                )
            }
            _ = try await agent.click(request)
            return try json(ActionResponse())
        }
    }

    private func type(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.TypeActionRequest.self, from: request)
        _ = try await activateAppIfRequested(action.app)
        _ = try await agent.type(ComputerUseAgentCore.TypeActionRequest(text: action.text))
        return try json(ActionResponse())
    }

    private func key(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.KeyActionRequest.self, from: request)
        _ = try await activateAppIfRequested(action.app)
        _ = try await agent.key(ComputerUseAgentCore.KeyActionRequest(
            key: action.key,
            modifiers: action.modifiers.map(coreModifier)
        ))
        return try json(ActionResponse())
    }

    private func drag(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.DragActionRequest.self, from: request)
        _ = try await activateAppIfRequested(action.app)
        _ = try await agent.drag(ComputerUseAgentCore.DragActionRequest(
            start: ComputerUseAgentCore.Point(x: action.from.x, y: action.from.y),
            end: ComputerUseAgentCore.Point(x: action.to.x, y: action.to.y)
        ))
        return try json(ActionResponse())
    }

    private func scroll(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.ScrollActionRequest.self, from: request)
        let appBundleIdentifier = try await activateAppIfRequested(action.app)
        let delta = scrollDelta(direction: action.direction, pages: action.pages)
        _ = try await agent.scroll(ComputerUseAgentCore.ScrollActionRequest(
            deltaX: delta.x,
            deltaY: delta.y,
            snapshotID: action.target.snapshotID,
            elementID: action.target.elementID,
            elementIndex: action.target.elementIndex,
            appBundleIdentifier: appBundleIdentifier
        ))
        return try json(ActionResponse())
    }

    private func setValue(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.SetValueActionRequest.self, from: request)
        let appBundleIdentifier = try await activateAppIfRequested(action.app)
        _ = try await agent.setValue(try coreSetValueRequest(
            reference: action.target,
            value: action.value,
            appBundleIdentifier: appBundleIdentifier
        ))
        return try json(ActionResponse())
    }

    private func perform(_ request: SessionAgentHTTPRequest) async throws -> SessionAgentHTTPResponse {
        let action = try decode(AgentProtocol.ElementActionRequest.self, from: request)
        let appBundleIdentifier = try await activateAppIfRequested(action.app)
        _ = try await agent.perform(try coreElementActionRequest(
            reference: action.target,
            name: action.name,
            appBundleIdentifier: appBundleIdentifier
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

    private func stateTargetBundleID(_ request: StateRequest) async throws -> String? {
        if request.app != nil && request.bundleID != nil {
            throw SessionAgentHTTPRouteError.agent(
                statusCode: 400,
                code: .invalidRequest,
                message: "state get accepts either app or bundle_id, not both"
            )
        }

        if let app = request.app {
            return try await agent.activateApplication(target: app).bundleIdentifier
        }

        return request.bundleID
    }

    private func activateAppIfRequested(_ app: String?) async throws -> String? {
        guard let app else {
            return nil
        }

        return try await agent.activateApplication(target: app).bundleIdentifier
    }

    private func appDescriptor(_ application: ComputerUseAgentCore.RunningApplication) -> ApplicationDescriptor {
        ApplicationDescriptor(
            bundleID: application.bundleIdentifier,
            name: application.name,
            pid: Int(application.processIdentifier)
        )
    }

    private func flatten(_ root: AccessibilityNode) -> [AXNode] {
        var nodes: [AXNode] = []
        var fallbackIndex = 0

        func walk(_ node: AccessibilityNode) {
            let index = node.index ?? fallbackIndex
            fallbackIndex += 1
            nodes.append(AXNode(
                index: index,
                id: node.id,
                role: node.role,
                title: node.title,
                value: node.value,
                bounds: node.frame.map(protocolRect),
                children: node.children.map(\.id),
                actions: node.actions
            ))

            node.children.forEach(walk)
        }

        walk(root)
        return nodes
    }

    private func readableAXTree(root: AccessibilityNode) -> String {
        var lines: [String] = []

        func walk(_ node: AccessibilityNode, depth: Int) {
            let index = node.index.map(String.init) ?? "-"
            var parts = ["\(String(repeating: "  ", count: depth))\(index) \(node.role)"]
            if let title = node.title, title.isEmpty == false {
                parts.append(title)
            }
            if let value = node.value, value.isEmpty == false {
                parts.append(value)
            }
            if node.actions.isEmpty == false {
                parts.append("Actions: \(node.actions.joined(separator: ", "))")
            }
            lines.append(parts.joined(separator: " "))
            node.children.forEach { walk($0, depth: depth + 1) }
        }

        walk(root, depth: 0)
        return lines.joined(separator: "\n")
    }

    private func protocolRect(_ rect: ComputerUseAgentCore.Rect) -> AgentProtocol.Rect {
        AgentProtocol.Rect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    private func scrollDelta(direction: ScrollDirection, pages: Double) -> (x: Double, y: Double) {
        let amount = max(pages, 0.1) * 800

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
            case let .elementIndexNotFound(snapshotID, elementIndex):
                return try self.error(
                    statusCode: 404,
                    code: .elementNotFound,
                    message: "Element index \(elementIndex) was not found in snapshot \(snapshotID)"
                )
            case let .snapshotAppMismatch(snapshotID, expectedBundleID, actualBundleID):
                return try self.error(
                    statusCode: 409,
                    code: .elementNotFound,
                    message: "Snapshot \(snapshotID) belongs to \(actualBundleID), not \(expectedBundleID)"
                )
            }
        } catch {
            return SessionAgentHTTPResponse(statusCode: 500)
        }
    }

    private func appActivationError(_ error: ApplicationActivationError) -> SessionAgentHTTPResponse {
        do {
            switch error {
            case let .appAmbiguous(target, candidates):
                let candidateList = candidates
                    .map { "\($0.name) (\($0.bundleIdentifier))" }
                    .joined(separator: ", ")
                return try self.error(
                    statusCode: 409,
                    code: .appAmbiguous,
                    message: "Application \(target) matched multiple candidates: \(candidateList)"
                )
            case let .appNotFound(target):
                return try self.error(
                    statusCode: 404,
                    code: .appNotFound,
                    message: "Application \(target) was not found"
                )
            case let .appLaunchFailed(target):
                return try self.error(
                    statusCode: 501,
                    code: .unsupportedAction,
                    message: "Application \(target) could not be launched"
                )
            case let .appWindowUnavailable(target):
                return try self.error(
                    statusCode: 504,
                    code: .appNotFound,
                    message: "Application \(target) did not expose a key window"
                )
            }
        } catch {
            return SessionAgentHTTPResponse(statusCode: 500)
        }
    }

    private func requiredElementID(_ reference: SnapshotElementReference) throws -> String {
        guard let elementID = reference.elementID else {
            throw SessionAgentHTTPRouteError.agent(
                statusCode: 400,
                code: .invalidRequest,
                message: "element_id is required"
            )
        }

        return elementID
    }

    private func requiredSnapshotID(_ reference: SnapshotElementReference) throws -> String {
        guard let snapshotID = reference.snapshotID else {
            throw SessionAgentHTTPRouteError.agent(
                statusCode: 400,
                code: .invalidRequest,
                message: "snapshot_id is required with element_id"
            )
        }

        return snapshotID
    }

    private func coreSetValueRequest(
        reference: SnapshotElementReference,
        value: String,
        appBundleIdentifier: String?
    ) throws -> ComputerUseAgentCore.SetValueActionRequest {
        if let elementIndex = reference.elementIndex {
            return ComputerUseAgentCore.SetValueActionRequest(
                elementIndex: elementIndex,
                value: value,
                snapshotID: reference.snapshotID,
                appBundleIdentifier: appBundleIdentifier
            )
        }

        return ComputerUseAgentCore.SetValueActionRequest(
            elementID: try requiredElementID(reference),
            value: value,
            snapshotID: try requiredSnapshotID(reference),
            appBundleIdentifier: appBundleIdentifier
        )
    }

    private func coreElementActionRequest(
        reference: SnapshotElementReference,
        name: String,
        appBundleIdentifier: String?
    ) throws -> ComputerUseAgentCore.ElementActionRequest {
        if let elementIndex = reference.elementIndex {
            return ComputerUseAgentCore.ElementActionRequest(
                elementIndex: elementIndex,
                actionName: name,
                snapshotID: reference.snapshotID,
                appBundleIdentifier: appBundleIdentifier
            )
        }

        return ComputerUseAgentCore.ElementActionRequest(
            elementID: try requiredElementID(reference),
            actionName: name,
            snapshotID: try requiredSnapshotID(reference),
            appBundleIdentifier: appBundleIdentifier
        )
    }

    private func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func coreModifier(_ modifier: AgentProtocol.KeyModifier) -> ComputerUseAgentCore.KeyModifier {
        switch modifier {
        case .command:
            .command
        case .shift:
            .shift
        case .option:
            .option
        case .control:
            .control
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
