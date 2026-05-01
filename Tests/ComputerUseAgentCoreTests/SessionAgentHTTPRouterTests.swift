import AgentProtocol
import ComputerUseAgentApp
import ComputerUseAgentCore
import CryptoKit
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
            isFrontmost: true,
            isRunning: true,
            lastUsed: "1970-01-01T01:06:40Z",
            uses: 3
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
    #expect(state.axTree.nodes.map(\.index) == [0, 1])
    #expect(state.axTreeText?.contains("0 AXWindow Untitled") == true)
    #expect(state.focusedElement?.id == "text")
    #expect(agent.stateBundleIdentifiers == ["com.apple.TextEdit"])

    let appStateRequest = SessionAgentHTTPRequest(
        method: .post,
        path: "/state",
        body: try AgentProtocolJSON.encode(StateRequest(app: "TextEdit"))
    )
    let appStateResponse = await router.handle(appStateRequest)
    #expect(appStateResponse.statusCode == 200)
    #expect(agent.activationTargets == ["TextEdit"])
    #expect(agent.stateBundleIdentifiers == ["com.apple.TextEdit", "com.apple.TextEdit"])

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

    let indexedClickRequest = SessionAgentHTTPRequest(
        method: .post,
        path: "/actions/click",
        body: try AgentProtocolJSON.encode(AgentProtocol.ClickActionRequest(
            target: .element(AgentProtocol.SnapshotElementReference(elementIndex: 1)),
            app: "TextEdit"
        ))
    )
    let indexedClickResponse = await router.handle(indexedClickRequest)
    #expect(indexedClickResponse.statusCode == 200)
    #expect(agent.clicks == [
        ComputerUseAgentCore.ClickActionRequest(location: ComputerUseAgentCore.Point(x: 10, y: 20)),
        ComputerUseAgentCore.ClickActionRequest(snapshotID: "snap-001", elementID: "text"),
        ComputerUseAgentCore.ClickActionRequest(elementIndex: 1, appBundleIdentifier: "com.apple.TextEdit"),
    ])
    #expect(agent.activationTargets == ["TextEdit", "TextEdit"])

    let keyRequest = SessionAgentHTTPRequest(
        method: .post,
        path: "/actions/key",
        body: try AgentProtocolJSON.encode(AgentProtocol.KeyActionRequest(
            key: "g",
            modifiers: [.command, .shift],
            app: "TextEdit"
        ))
    )
    let keyResponse = await router.handle(keyRequest)
    #expect(keyResponse.statusCode == 200)
    #expect(agent.keys == [
        ComputerUseAgentCore.KeyActionRequest(key: "g", modifiers: [.command, .shift]),
    ])
}

@Test
func sessionAgentHTTPRouterTransfersFilesInChunks() async throws {
    let guestHome = try routerTemporaryDirectory()
    let guestTemporaryDirectory = try routerTemporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: guestHome)
        try? FileManager.default.removeItem(at: guestTemporaryDirectory)
    }

    let router = SessionAgentHTTPRouter(
        agent: StubSessionAgent(),
        fileTransferHomeDirectory: guestHome,
        fileTransferTemporaryDirectory: guestTemporaryDirectory
    )
    let payload = Data("hello world".utf8)
    let payloadSHA256 = sha256Hex(payload)

    let startUploadResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/upload/start",
        body: try AgentProtocolJSON.encode(FileUploadStartRequest(
            path: "~/Documents/hello.txt",
            expectedBytes: Int64(payload.count),
            sha256: payloadSHA256,
            overwrite: false,
            createDirectories: true
        ))
    ))
    #expect(startUploadResponse.statusCode == 200)
    let upload = try AgentProtocolJSON.decode(FileUploadStartResponse.self, from: startUploadResponse.body)
    #expect(upload.path == guestHome.appendingPathComponent("Documents/hello.txt").path)

    let firstChunk = Data(payload.prefix(5))
    let firstChunkResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/upload/chunk",
        body: try AgentProtocolJSON.encode(FileUploadChunkRequest(
            uploadID: upload.uploadID,
            offset: 0,
            base64: firstChunk.base64EncodedString(),
            sha256: sha256Hex(firstChunk)
        ))
    ))
    #expect(firstChunkResponse.statusCode == 200)

    let secondChunk = Data(payload.dropFirst(5))
    let secondChunkResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/upload/chunk",
        body: try AgentProtocolJSON.encode(FileUploadChunkRequest(
            uploadID: upload.uploadID,
            offset: Int64(firstChunk.count),
            base64: secondChunk.base64EncodedString(),
            sha256: sha256Hex(secondChunk)
        ))
    ))
    #expect(secondChunkResponse.statusCode == 200)

    let finishUploadResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/upload/finish",
        body: try AgentProtocolJSON.encode(FileUploadFinishRequest(uploadID: upload.uploadID))
    ))
    #expect(finishUploadResponse.statusCode == 200)
    let uploadResult = try AgentProtocolJSON.decode(FileTransferResponse.self, from: finishUploadResponse.body)
    #expect(uploadResult.bytes == Int64(payload.count))
    #expect(uploadResult.sha256 == payloadSHA256)
    #expect(try Data(contentsOf: URL(fileURLWithPath: uploadResult.path)) == payload)

    let statResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/stat",
        body: try AgentProtocolJSON.encode(FileStatRequest(path: "~/Documents/hello.txt"))
    ))
    #expect(statResponse.statusCode == 200)
    let stat = try AgentProtocolJSON.decode(FileStatResponse.self, from: statResponse.body)
    #expect(stat.kind == .file)
    #expect(stat.bytes == Int64(payload.count))
    #expect(stat.sha256 == payloadSHA256)

    let startDownloadResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/download/start",
        body: try AgentProtocolJSON.encode(FileDownloadStartRequest(path: "~/Documents/hello.txt"))
    ))
    #expect(startDownloadResponse.statusCode == 200)
    let download = try AgentProtocolJSON.decode(FileDownloadStartResponse.self, from: startDownloadResponse.body)
    #expect(download.bytes == Int64(payload.count))
    #expect(download.sha256 == payloadSHA256)

    let downloadChunkResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/download/chunk",
        body: try AgentProtocolJSON.encode(FileDownloadChunkRequest(
            downloadID: download.downloadID,
            offset: 0,
            length: 64
        ))
    ))
    #expect(downloadChunkResponse.statusCode == 200)
    let downloadChunk = try AgentProtocolJSON.decode(
        FileDownloadChunkResponse.self,
        from: downloadChunkResponse.body
    )
    #expect(downloadChunk.eof)
    #expect(Data(base64Encoded: downloadChunk.base64) == payload)
    #expect(downloadChunk.sha256 == payloadSHA256)

    let finishDownloadResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/download/finish",
        body: try AgentProtocolJSON.encode(FileDownloadFinishRequest(downloadID: download.downloadID))
    ))
    #expect(finishDownloadResponse.statusCode == 200)
}

@Test
func sessionAgentHTTPRouterTransfersDirectoriesAsArchives() async throws {
    let guestHome = try routerTemporaryDirectory()
    let guestTemporaryDirectory = try routerTemporaryDirectory()
    let sourceDirectory = try routerTemporaryDirectory()
    let extractDirectory = try routerTemporaryDirectory()
    defer {
        try? FileManager.default.removeItem(at: guestHome)
        try? FileManager.default.removeItem(at: guestTemporaryDirectory)
        try? FileManager.default.removeItem(at: sourceDirectory)
        try? FileManager.default.removeItem(at: extractDirectory)
    }

    let nestedDirectory = sourceDirectory.appendingPathComponent("Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
    try Data("directory payload".utf8).write(to: nestedDirectory.appendingPathComponent("payload.txt"))

    let archiveURL = sourceDirectory.deletingLastPathComponent()
        .appendingPathComponent("\(UUID().uuidString).tar.gz")
    defer {
        try? FileManager.default.removeItem(at: archiveURL)
    }
    try runTar(arguments: [
        "-C", sourceDirectory.path,
        "-czf", archiveURL.path,
        ".",
    ])
    let archiveData = try Data(contentsOf: archiveURL)

    let router = SessionAgentHTTPRouter(
        agent: StubSessionAgent(),
        fileTransferHomeDirectory: guestHome,
        fileTransferTemporaryDirectory: guestTemporaryDirectory
    )

    let startUploadResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/upload/start",
        body: try AgentProtocolJSON.encode(FileUploadStartRequest(
            path: "~/Imported",
            expectedBytes: Int64(archiveData.count),
            sha256: sha256Hex(archiveData),
            archiveFormat: .tarGzip
        ))
    ))
    #expect(startUploadResponse.statusCode == 200)
    let upload = try AgentProtocolJSON.decode(FileUploadStartResponse.self, from: startUploadResponse.body)

    let chunkResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/upload/chunk",
        body: try AgentProtocolJSON.encode(FileUploadChunkRequest(
            uploadID: upload.uploadID,
            offset: 0,
            base64: archiveData.base64EncodedString(),
            sha256: sha256Hex(archiveData)
        ))
    ))
    #expect(chunkResponse.statusCode == 200)

    let finishUploadResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/upload/finish",
        body: try AgentProtocolJSON.encode(FileUploadFinishRequest(uploadID: upload.uploadID))
    ))
    #expect(finishUploadResponse.statusCode == 200)
    let importedPayload = guestHome
        .appendingPathComponent("Imported/Nested/payload.txt")
    #expect(try String(contentsOf: importedPayload, encoding: .utf8) == "directory payload")

    let statResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/stat",
        body: try AgentProtocolJSON.encode(FileStatRequest(path: "~/Imported"))
    ))
    #expect(statResponse.statusCode == 200)
    let stat = try AgentProtocolJSON.decode(FileStatResponse.self, from: statResponse.body)
    #expect(stat.kind == .directory)

    let startDownloadResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/download/start",
        body: try AgentProtocolJSON.encode(FileDownloadStartRequest(
            path: "~/Imported",
            archiveFormat: .tarGzip
        ))
    ))
    #expect(startDownloadResponse.statusCode == 200)
    let download = try AgentProtocolJSON.decode(FileDownloadStartResponse.self, from: startDownloadResponse.body)

    let downloadChunkResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/download/chunk",
        body: try AgentProtocolJSON.encode(FileDownloadChunkRequest(
            downloadID: download.downloadID,
            offset: 0,
            length: Int(download.bytes)
        ))
    ))
    #expect(downloadChunkResponse.statusCode == 200)
    let downloadedChunk = try AgentProtocolJSON.decode(
        FileDownloadChunkResponse.self,
        from: downloadChunkResponse.body
    )
    let downloadedArchiveURL = extractDirectory.appendingPathComponent("downloaded.tar.gz")
    try Data(base64Encoded: downloadedChunk.base64)?.write(to: downloadedArchiveURL)
    try runTar(arguments: [
        "-xzf", downloadedArchiveURL.path,
        "-C", extractDirectory.path,
    ])
    #expect(try String(
        contentsOf: extractDirectory.appendingPathComponent("Nested/payload.txt"),
        encoding: .utf8
    ) == "directory payload")

    let finishDownloadResponse = await router.handle(SessionAgentHTTPRequest(
        method: .post,
        path: "/files/download/finish",
        body: try AgentProtocolJSON.encode(FileDownloadFinishRequest(downloadID: download.downloadID))
    ))
    #expect(finishDownloadResponse.statusCode == 200)
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

private func routerTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func runTar(arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
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
            isFrontmost: true,
            lastUsed: Date(timeIntervalSince1970: 4_000),
            useCount: 3
        ),
    ]
    private(set) var clicks: [ComputerUseAgentCore.ClickActionRequest] = []
    private(set) var keys: [ComputerUseAgentCore.KeyActionRequest] = []
    private(set) var stateBundleIdentifiers: [String?] = []
    private(set) var activationTargets: [String] = []

    func currentPermissions() async throws -> PermissionSnapshot {
        permissions
    }

    func requestPermissions() async throws -> PermissionSnapshot {
        permissions
    }

    func runningApplications() async throws -> [ComputerUseAgentCore.RunningApplication] {
        applications
    }

    func activateApplication(target: String) async throws -> ComputerUseAgentCore.RunningApplication {
        activationTargets.append(target)
        return applications[0]
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
                index: 0,
                id: "root",
                role: "AXWindow",
                title: "Untitled",
                frame: Rect(
                    origin: Point(x: 0, y: 0),
                    size: Size(width: 200, height: 100)
                ),
                children: [
                    AccessibilityNode(
                        index: 1,
                        id: "text",
                        role: "AXTextArea",
                        value: "hello",
                        actions: ["AXPress"]
                    ),
                ]
            ),
            applications: applications,
            focusedElementID: "text"
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
        keys.append(request)
        return ActionReceipt(accepted: true)
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
