import XCTest
@testable import AgentProtocol

final class AgentProtocolRoundTripTests: XCTestCase {
    func testHealthPermissionsAndAppsResponsesRoundTrip() throws {
        try assertRoundTrip(
            HealthResponse(ok: true, version: "0.1.0"),
            expectedJSON: #"{"ok":true,"version":"0.1.0"}"#
        )

        try assertRoundTrip(
            PermissionsResponse(accessibility: true, screenRecording: false),
            expectedJSON: #"{"accessibility":true,"screen_recording":false}"#
        )

        try assertRoundTrip(
            AppsResponse(
                apps: [
                    RunningApplication(bundleID: "com.apple.TextEdit", name: "TextEdit", pid: 123, isFrontmost: true),
                    RunningApplication(bundleID: "com.apple.finder", name: "Finder", pid: 99, isFrontmost: false),
                ]
            ),
            expectedJSON: #"{"apps":[{"bundle_id":"com.apple.TextEdit","is_frontmost":true,"name":"TextEdit","pid":123},{"bundle_id":"com.apple.finder","is_frontmost":false,"name":"Finder","pid":99}]}"#
        )

        try assertRoundTrip(
            AppsResponse(
                apps: [
                    RunningApplication(
                        bundleID: "com.apple.TextEdit",
                        name: "TextEdit",
                        pid: 123,
                        isFrontmost: true,
                        isRunning: true,
                        lastUsed: "2026-04-26T12:00:00Z",
                        uses: 2
                    ),
                ]
            ),
            expectedJSON: #"{"apps":[{"bundle_id":"com.apple.TextEdit","is_frontmost":true,"is_running":true,"last_used":"2026-04-26T12:00:00Z","name":"TextEdit","pid":123,"uses":2}]}"#
        )
    }

    func testStateRequestAndResponseRoundTrip() throws {
        try assertRoundTrip(
            StateRequest(bundleID: "com.apple.TextEdit"),
            expectedJSON: #"{"bundle_id":"com.apple.TextEdit"}"#
        )

        try assertRoundTrip(
            StateRequest(app: "TextEdit"),
            expectedJSON: #"{"app":"TextEdit"}"#
        )

        try assertRoundTrip(
            AppActivationRequest(app: "TextEdit"),
            expectedJSON: #"{"app":"TextEdit"}"#
        )

        try assertRoundTrip(
            AppActivationResponse(app: ApplicationDescriptor(bundleID: "com.apple.TextEdit", name: "TextEdit", pid: 123)),
            expectedJSON: #"{"app":{"bundle_id":"com.apple.TextEdit","name":"TextEdit","pid":123}}"#
        )

        let response = StateResponse(
            snapshotID: "snap-001",
            app: ApplicationDescriptor(bundleID: "com.apple.TextEdit", name: "TextEdit", pid: 123),
            window: WindowDescriptor(
                title: "Untitled",
                bounds: Rect(x: 120, y: 80, width: 1024, height: 768)
            ),
            screenshot: ScreenshotPayload(mimeType: "image/png", base64: "ZmFrZS1wbmc="),
            axTree: AXTree(
                rootID: "ax-1",
                nodes: [
                    AXNode(
                        id: "ax-1",
                        role: "AXWindow",
                        title: "Untitled",
                        bounds: Rect(x: 120, y: 80, width: 1024, height: 768),
                        children: ["ax-2"],
                        actions: ["AXRaise"]
                    ),
                    AXNode(
                        id: "ax-2",
                        role: "AXTextArea",
                        value: "hello",
                        children: [],
                        actions: ["AXConfirm", "AXPress"]
                    ),
                ]
            )
        )

        try assertRoundTrip(
            response,
            expectedJSON: #"{"app":{"bundle_id":"com.apple.TextEdit","name":"TextEdit","pid":123},"ax_tree":{"nodes":[{"actions":["AXRaise"],"bounds":{"height":768,"width":1024,"x":120,"y":80},"children":["ax-2"],"id":"ax-1","role":"AXWindow","title":"Untitled"},{"actions":["AXConfirm","AXPress"],"children":[],"id":"ax-2","role":"AXTextArea","value":"hello"}],"root_id":"ax-1"},"screenshot":{"base64":"ZmFrZS1wbmc=","mime_type":"image/png"},"snapshot_id":"snap-001","window":{"bounds":{"height":768,"width":1024,"x":120,"y":80},"title":"Untitled"}}"#
        )
    }

    func testActionRequestsRoundTrip() throws {
        try assertRoundTrip(
            ClickActionRequest(
                target: .coordinates(Point(x: 100, y: 200)),
                button: .left,
                clickCount: 1
            ),
            expectedJSON: #"{"button":"left","click_count":1,"x":100,"y":200}"#
        )

        try assertRoundTrip(
            ClickActionRequest(
                target: .element(SnapshotElementReference(snapshotID: "snap-001", elementID: "ax-42")),
                button: .right,
                clickCount: 2
            ),
            expectedJSON: #"{"button":"right","click_count":2,"element_id":"ax-42","snapshot_id":"snap-001"}"#
        )

        try assertRoundTrip(
            TypeActionRequest(text: "hello"),
            expectedJSON: #"{"text":"hello"}"#
        )

        try assertRoundTrip(
            KeyActionRequest(key: "Return"),
            expectedJSON: #"{"key":"Return"}"#
        )

        try assertRoundTrip(
            KeyActionRequest(key: "g", modifiers: [.command, .shift], app: "TextEdit"),
            expectedJSON: #"{"app":"TextEdit","key":"g","modifiers":["command","shift"]}"#
        )

        try assertRoundTrip(
            DragActionRequest(from: Point(x: 100, y: 100), to: Point(x: 400, y: 300)),
            expectedJSON: #"{"from":{"x":100,"y":100},"to":{"x":400,"y":300}}"#
        )

        try assertRoundTrip(
            ScrollActionRequest(
                target: SnapshotElementReference(snapshotID: "snap-001", elementID: "ax-21"),
                direction: .down,
                pages: 1
            ),
            expectedJSON: #"{"direction":"down","element_id":"ax-21","pages":1,"snapshot_id":"snap-001"}"#
        )

        try assertRoundTrip(
            ScrollActionRequest(
                target: SnapshotElementReference(snapshotID: "snap-001", elementIndex: 3),
                direction: .down,
                pages: 0.5,
                app: "TextEdit"
            ),
            expectedJSON: #"{"app":"TextEdit","direction":"down","element_index":3,"pages":0.5,"snapshot_id":"snap-001"}"#
        )

        try assertRoundTrip(
            SetValueActionRequest(
                target: SnapshotElementReference(snapshotID: "snap-001", elementID: "ax-12"),
                value: "new value"
            ),
            expectedJSON: #"{"element_id":"ax-12","snapshot_id":"snap-001","value":"new value"}"#
        )

        try assertRoundTrip(
            ElementActionRequest(
                target: SnapshotElementReference(snapshotID: "snap-001", elementID: "ax-12"),
                name: "AXPress"
            ),
            expectedJSON: #"{"element_id":"ax-12","name":"AXPress","snapshot_id":"snap-001"}"#
        )

        try assertRoundTrip(
            ActionResponse(),
            expectedJSON: #"{"ok":true}"#
        )
    }

    func testFileTransferRequestsRoundTrip() throws {
        try assertRoundTrip(
            FileUploadStartRequest(
                path: "~/Desktop/a.txt",
                expectedBytes: 11,
                sha256: "abc",
                overwrite: false,
                createDirectories: true
            ),
            expectedJSON: #"{"create_directories":true,"expected_bytes":11,"overwrite":false,"path":"~/Desktop/a.txt","sha256":"abc"}"#
        )

        try assertRoundTrip(
            FileUploadStartResponse(uploadID: "up-1", path: "/Users/admin/Desktop/a.txt"),
            expectedJSON: #"{"path":"/Users/admin/Desktop/a.txt","upload_id":"up-1"}"#
        )

        try assertRoundTrip(
            FileUploadChunkRequest(
                uploadID: "up-1",
                offset: 0,
                base64: "aGVsbG8=",
                sha256: "def"
            ),
            expectedJSON: #"{"base64":"aGVsbG8=","offset":0,"sha256":"def","upload_id":"up-1"}"#
        )

        try assertRoundTrip(
            FileUploadChunkResponse(uploadID: "up-1", offset: 0, bytes: 5, receivedBytes: 5),
            expectedJSON: #"{"bytes":5,"offset":0,"received_bytes":5,"upload_id":"up-1"}"#
        )

        try assertRoundTrip(
            FileUploadFinishRequest(uploadID: "up-1"),
            expectedJSON: #"{"upload_id":"up-1"}"#
        )

        try assertRoundTrip(
            FileDownloadStartRequest(path: "~/Desktop/a.txt"),
            expectedJSON: #"{"path":"~/Desktop/a.txt"}"#
        )

        try assertRoundTrip(
            FileDownloadStartResponse(
                downloadID: "down-1",
                path: "/Users/admin/Desktop/a.txt",
                bytes: 11,
                sha256: "abc"
            ),
            expectedJSON: #"{"bytes":11,"download_id":"down-1","path":"/Users/admin/Desktop/a.txt","sha256":"abc"}"#
        )

        try assertRoundTrip(
            FileDownloadChunkRequest(downloadID: "down-1", offset: 5, length: 6),
            expectedJSON: #"{"download_id":"down-1","length":6,"offset":5}"#
        )

        try assertRoundTrip(
            FileDownloadChunkResponse(
                downloadID: "down-1",
                offset: 5,
                base64: "IHdvcmxk",
                bytes: 6,
                sha256: "def",
                eof: true
            ),
            expectedJSON: #"{"base64":"IHdvcmxk","bytes":6,"download_id":"down-1","eof":true,"offset":5,"sha256":"def"}"#
        )

        try assertRoundTrip(
            FileDownloadFinishRequest(downloadID: "down-1"),
            expectedJSON: #"{"download_id":"down-1"}"#
        )

        try assertRoundTrip(
            FileTransferResponse(path: "/Users/admin/Desktop/a.txt", bytes: 11, sha256: "abc"),
            expectedJSON: #"{"bytes":11,"path":"/Users/admin/Desktop/a.txt","sha256":"abc"}"#
        )
    }

    func testErrorResponseRoundTrip() throws {
        try assertRoundTrip(
            ErrorResponse(
                error: AgentError(
                    code: .permissionDenied,
                    message: "Accessibility permission is not granted"
                )
            ),
            expectedJSON: #"{"error":{"code":"permission_denied","message":"Accessibility permission is not granted"}}"#
        )

        try assertRoundTrip(
            ErrorResponse(
                error: AgentError(
                    code: .snapshotExpired,
                    message: "Snapshot snap-001 has expired"
                )
            ),
            expectedJSON: #"{"error":{"code":"snapshot_expired","message":"Snapshot snap-001 has expired"}}"#
        )
    }

    private func assertRoundTrip<Value: Codable & Equatable>(
        _ value: Value,
        expectedJSON: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoded = try AgentProtocolJSON.encode(value)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), expectedJSON, file: file, line: line)

        let decoded = try AgentProtocolJSON.decode(Value.self, from: Data(expectedJSON.utf8))
        XCTAssertEqual(decoded, value, file: file, line: line)

        let reencoded = try AgentProtocolJSON.encode(decoded)
        XCTAssertEqual(reencoded, Data(expectedJSON.utf8), file: file, line: line)
    }
}
