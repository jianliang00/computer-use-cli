import AgentProtocol
import ComputerUseAgentApp
import ComputerUseAgentCore
import Foundation
import Testing

@Test
func sessionAgentHTTPRouterServesHealthPermissionsAndApps() async throws {
    let agent = StubSessionAgent()
    let router = SessionAgentHTTPRouter(agent: agent)

    let healthResponse = await router.handle(SessionAgentHTTPRequest(method: .get, path: "/health"))
    #expect(healthResponse.statusCode == 200)
    let health = try AgentProtocolJSON.decode(HealthResponse.self, from: healthResponse.body)
    #expect(health.ok)

    let permissionsResponse = await router.handle(SessionAgentHTTPRequest(method: .get, path: "/permissions"))
    #expect(permissionsResponse.statusCode == 200)
    let permissions = try AgentProtocolJSON.decode(PermissionsResponse.self, from: permissionsResponse.body)
    #expect(permissions.accessibility)
    #expect(permissions.screenRecording)

    let permissionRequestResponse = await router.handle(SessionAgentHTTPRequest(method: .post, path: "/permissions/request"))
    #expect(permissionRequestResponse.statusCode == 200)
    let requestedPermissions = try AgentProtocolJSON.decode(PermissionsResponse.self, from: permissionRequestResponse.body)
    #expect(requestedPermissions.accessibility)
    #expect(requestedPermissions.screenRecording)

    let appsResponse = await router.handle(SessionAgentHTTPRequest(method: .get, path: "/apps"))
    #expect(appsResponse.statusCode == 200)
    let apps = try AgentProtocolJSON.decode(AppsResponse.self, from: appsResponse.body)
    #expect(apps.apps == [
        AgentProtocol.RunningApplication(
            bundleID: "com.apple.TextEdit",
            name: "TextEdit",
            pid: 123,
            isFrontmost: true
        ),
    ])
}

@Test
func sessionAgentHTTPRouterMapsStateAndActions() async throws {
    let agent = StubSessionAgent()
    let router = SessionAgentHTTPRouter(agent: agent)

    let stateRequest = SessionAgentHTTPRequest(
        method: .post,
        path: "/state",
        body: try AgentProtocolJSON.encode(StateRequest(bundleID: "com.apple.TextEdit"))
    )
    let stateResponse = await router.handle(stateRequest)
    #expect(stateResponse.statusCode == 200)

    let state = try AgentProtocolJSON.decode(StateResponse.self, from: stateResponse.body)
    #expect(state.snapshotID == "snap-001")
    #expect(state.app.bundleID == "com.apple.TextEdit")
    #expect(state.screenshot.base64 == Data([1, 2, 3]).base64EncodedString())
    #expect(state.axTree.nodes.map(\.id) == ["root", "text"])
    #expect(agent.stateBundleIdentifiers == ["com.apple.TextEdit"])

    let clickRequest = SessionAgentHTTPRequest(
        method: .post,
        path: "/actions/click",
        body: try AgentProtocolJSON.encode(AgentProtocol.ClickActionRequest(
            target: .coordinates(AgentProtocol.Point(x: 10, y: 20))
        ))
    )
    let clickResponse = await router.handle(clickRequest)
    #expect(clickResponse.statusCode == 200)

    let elementClickRequest = SessionAgentHTTPRequest(
        method: .post,
        path: "/actions/click",
        body: try AgentProtocolJSON.encode(AgentProtocol.ClickActionRequest(
            target: .element(AgentProtocol.SnapshotElementReference(
                snapshotID: "snap-001",
                elementID: "text"
            ))
        ))
    )
    let elementClickResponse = await router.handle(elementClickRequest)
    #expect(elementClickResponse.statusCode == 200)
    #expect(agent.clicks == [
        ComputerUseAgentCore.ClickActionRequest(location: ComputerUseAgentCore.Point(x: 10, y: 20)),
        ComputerUseAgentCore.ClickActionRequest(snapshotID: "snap-001", elementID: "text"),
    ])
}

@Test
func sessionAgentHTTPRouterRejectsAutomationWhenPermissionsAreMissing() async throws {
    let agent = StubSessionAgent()
    agent.permissions = PermissionSnapshot(
        accessibility: .authorized,
        screenRecording: .denied
    )
    let router = SessionAgentHTTPRouter(agent: agent)

    let request = SessionAgentHTTPRequest(
        method: .post,
        path: "/actions/type",
        body: try AgentProtocolJSON.encode(AgentProtocol.TypeActionRequest(text: "hello"))
    )
    let response = await router.handle(request)

    #expect(response.statusCode == 403)
    let error = try AgentProtocolJSON.decode(ErrorResponse.self, from: response.body)
    #expect(error.error.code == .permissionDenied)
}

private final class StubSessionAgent: ComputerUseSessionAgent, @unchecked Sendable {
    var permissions = PermissionSnapshot(
        accessibility: .authorized,
        screenRecording: .authorized
    )
    var applications = [
        ComputerUseAgentCore.RunningApplication(
            bundleIdentifier: "com.apple.TextEdit",
            name: "TextEdit",
            processIdentifier: 123,
            isFrontmost: true
        ),
    ]
    private(set) var clicks: [ComputerUseAgentCore.ClickActionRequest] = []
    private(set) var stateBundleIdentifiers: [String?] = []

    func currentPermissions() async throws -> PermissionSnapshot {
        permissions
    }

    func requestPermissions() async throws -> PermissionSnapshot {
        permissions
    }

    func runningApplications() async throws -> [ComputerUseAgentCore.RunningApplication] {
        applications
    }

    func captureState(bundleIdentifier: String?) async throws -> AgentStateSnapshot {
        stateBundleIdentifiers.append(bundleIdentifier)
        return AgentStateSnapshot(
            snapshotID: "snap-001",
            screenshot: ScreenshotFrame(
                encoding: .png,
                size: Size(width: 200, height: 100),
                bytes: [1, 2, 3]
            ),
            accessibilityRoot: AccessibilityNode(
                id: "root",
                role: "AXWindow",
                title: "Untitled",
                frame: Rect(
                    origin: Point(x: 0, y: 0),
                    size: Size(width: 200, height: 100)
                ),
                children: [
                    AccessibilityNode(
                        id: "text",
                        role: "AXTextArea",
                        value: "hello"
                    ),
                ]
            ),
            applications: applications
        )
    }

    func click(_ request: ComputerUseAgentCore.ClickActionRequest) async throws -> ActionReceipt {
        clicks.append(request)
        return ActionReceipt(accepted: true)
    }

    func type(_ request: ComputerUseAgentCore.TypeActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func key(_ request: ComputerUseAgentCore.KeyActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func drag(_ request: ComputerUseAgentCore.DragActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func scroll(_ request: ComputerUseAgentCore.ScrollActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func setValue(_ request: ComputerUseAgentCore.SetValueActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func perform(_ request: ComputerUseAgentCore.ElementActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }
}
