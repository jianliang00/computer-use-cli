import Foundation

public struct HealthResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var version: String

    public init(ok: Bool, version: String) {
        self.ok = ok
        self.version = version
    }
}

public struct PermissionsResponse: Codable, Sendable, Equatable {
    public var accessibility: Bool
    public var screenRecording: Bool

    public init(accessibility: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    private enum CodingKeys: String, CodingKey {
        case accessibility
        case screenRecording = "screen_recording"
    }
}

public struct AppsResponse: Codable, Sendable, Equatable {
    public var apps: [RunningApplication]

    public init(apps: [RunningApplication]) {
        self.apps = apps
    }
}

public struct AppActivationRequest: Codable, Sendable, Equatable {
    public var app: String

    public init(app: String) {
        self.app = app
    }
}

public struct AppActivationResponse: Codable, Sendable, Equatable {
    public var app: ApplicationDescriptor

    public init(app: ApplicationDescriptor) {
        self.app = app
    }
}

public struct StateRequest: Codable, Sendable, Equatable {
    public var bundleID: String?
    public var app: String?

    public init(bundleID: String? = nil, app: String? = nil) {
        self.bundleID = bundleID
        self.app = app
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case app
    }
}

public struct StateResponse: Codable, Sendable, Equatable {
    public var snapshotID: String
    public var app: ApplicationDescriptor
    public var window: WindowDescriptor?
    public var screenshot: ScreenshotPayload
    public var axTree: AXTree
    public var axTreeText: String?
    public var focusedElement: AXNode?

    public init(
        snapshotID: String,
        app: ApplicationDescriptor,
        window: WindowDescriptor?,
        screenshot: ScreenshotPayload,
        axTree: AXTree,
        axTreeText: String? = nil,
        focusedElement: AXNode? = nil
    ) {
        self.snapshotID = snapshotID
        self.app = app
        self.window = window
        self.screenshot = screenshot
        self.axTree = axTree
        self.axTreeText = axTreeText
        self.focusedElement = focusedElement
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case app
        case window
        case screenshot
        case axTree = "ax_tree"
        case axTreeText = "ax_tree_text"
        case focusedElement = "focused_element"
    }
}

public struct ActionResponse: Codable, Sendable, Equatable {
    public var ok: Bool

    public init(ok: Bool = true) {
        self.ok = ok
    }
}

public struct FileUploadStartRequest: Codable, Sendable, Equatable {
    public var path: String
    public var expectedBytes: Int64?
    public var sha256: String?
    public var overwrite: Bool
    public var createDirectories: Bool

    public init(
        path: String,
        expectedBytes: Int64? = nil,
        sha256: String? = nil,
        overwrite: Bool = true,
        createDirectories: Bool = true
    ) {
        self.path = path
        self.expectedBytes = expectedBytes
        self.sha256 = sha256
        self.overwrite = overwrite
        self.createDirectories = createDirectories
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case expectedBytes = "expected_bytes"
        case sha256
        case overwrite
        case createDirectories = "create_directories"
    }
}

public struct FileUploadStartResponse: Codable, Sendable, Equatable {
    public var uploadID: String
    public var path: String

    public init(uploadID: String, path: String) {
        self.uploadID = uploadID
        self.path = path
    }

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case path
    }
}

public struct FileUploadChunkRequest: Codable, Sendable, Equatable {
    public var uploadID: String
    public var offset: Int64
    public var base64: String
    public var sha256: String?

    public init(
        uploadID: String,
        offset: Int64,
        base64: String,
        sha256: String? = nil
    ) {
        self.uploadID = uploadID
        self.offset = offset
        self.base64 = base64
        self.sha256 = sha256
    }

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case offset
        case base64
        case sha256
    }
}

public struct FileUploadChunkResponse: Codable, Sendable, Equatable {
    public var uploadID: String
    public var offset: Int64
    public var bytes: Int64
    public var receivedBytes: Int64

    public init(
        uploadID: String,
        offset: Int64,
        bytes: Int64,
        receivedBytes: Int64
    ) {
        self.uploadID = uploadID
        self.offset = offset
        self.bytes = bytes
        self.receivedBytes = receivedBytes
    }

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case offset
        case bytes
        case receivedBytes = "received_bytes"
    }
}

public struct FileUploadFinishRequest: Codable, Sendable, Equatable {
    public var uploadID: String

    public init(uploadID: String) {
        self.uploadID = uploadID
    }

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
    }
}

public struct FileDownloadStartRequest: Codable, Sendable, Equatable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct FileDownloadStartResponse: Codable, Sendable, Equatable {
    public var downloadID: String
    public var path: String
    public var bytes: Int64
    public var sha256: String

    public init(
        downloadID: String,
        path: String,
        bytes: Int64,
        sha256: String
    ) {
        self.downloadID = downloadID
        self.path = path
        self.bytes = bytes
        self.sha256 = sha256
    }

    private enum CodingKeys: String, CodingKey {
        case downloadID = "download_id"
        case path
        case bytes
        case sha256
    }
}

public struct FileDownloadChunkRequest: Codable, Sendable, Equatable {
    public var downloadID: String
    public var offset: Int64
    public var length: Int

    public init(
        downloadID: String,
        offset: Int64,
        length: Int
    ) {
        self.downloadID = downloadID
        self.offset = offset
        self.length = length
    }

    private enum CodingKeys: String, CodingKey {
        case downloadID = "download_id"
        case offset
        case length
    }
}

public struct FileDownloadChunkResponse: Codable, Sendable, Equatable {
    public var downloadID: String
    public var offset: Int64
    public var base64: String
    public var bytes: Int64
    public var sha256: String
    public var eof: Bool

    public init(
        downloadID: String,
        offset: Int64,
        base64: String,
        bytes: Int64,
        sha256: String,
        eof: Bool
    ) {
        self.downloadID = downloadID
        self.offset = offset
        self.base64 = base64
        self.bytes = bytes
        self.sha256 = sha256
        self.eof = eof
    }

    private enum CodingKeys: String, CodingKey {
        case downloadID = "download_id"
        case offset
        case base64
        case bytes
        case sha256
        case eof
    }
}

public struct FileDownloadFinishRequest: Codable, Sendable, Equatable {
    public var downloadID: String

    public init(downloadID: String) {
        self.downloadID = downloadID
    }

    private enum CodingKeys: String, CodingKey {
        case downloadID = "download_id"
    }
}

public struct FileTransferResponse: Codable, Sendable, Equatable {
    public var path: String
    public var bytes: Int64
    public var sha256: String

    public init(path: String, bytes: Int64, sha256: String) {
        self.path = path
        self.bytes = bytes
        self.sha256 = sha256
    }
}

public struct ClickActionRequest: Codable, Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case coordinates(Point)
        case element(SnapshotElementReference)
    }

    public var target: Target
    public var button: MouseButton
    public var clickCount: Int
    public var app: String?

    public init(
        target: Target,
        button: MouseButton = .left,
        clickCount: Int = 1,
        app: String? = nil
    ) {
        self.target = target
        self.button = button
        self.clickCount = clickCount
        self.app = app
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case x
        case y
        case snapshotID = "snapshot_id"
        case elementID = "element_id"
        case elementIndex = "element_index"
        case button
        case clickCount = "click_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decodeIfPresent(Double.self, forKey: .x)
        let y = try container.decodeIfPresent(Double.self, forKey: .y)
        let snapshotID = try container.decodeIfPresent(String.self, forKey: .snapshotID)
        let elementID = try container.decodeIfPresent(String.self, forKey: .elementID)
        let elementIndex = try container.decodeIfPresent(Int.self, forKey: .elementIndex)

        switch (x, y, snapshotID, elementID, elementIndex) {
        case let (.some(x), .some(y), nil, nil, nil):
            target = .coordinates(Point(x: x, y: y))
        case let (nil, nil, .some(snapshotID), .some(elementID), nil):
            target = .element(SnapshotElementReference(snapshotID: snapshotID, elementID: elementID))
        case let (nil, nil, snapshotID, nil, .some(elementIndex)):
            target = .element(SnapshotElementReference(snapshotID: snapshotID, elementIndex: elementIndex))
        default:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "ClickActionRequest must include either x/y, snapshot_id/element_id, or element_index."
                )
            )
        }

        app = try container.decodeIfPresent(String.self, forKey: .app)
        button = try container.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left
        clickCount = try container.decodeIfPresent(Int.self, forKey: .clickCount) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch target {
        case let .coordinates(point):
            try container.encode(point.x, forKey: .x)
            try container.encode(point.y, forKey: .y)
        case let .element(reference):
            try container.encodeIfPresent(reference.snapshotID, forKey: .snapshotID)
            try container.encodeIfPresent(reference.elementID, forKey: .elementID)
            try container.encodeIfPresent(reference.elementIndex, forKey: .elementIndex)
        }

        try container.encodeIfPresent(app, forKey: .app)
        try container.encode(button, forKey: .button)
        try container.encode(clickCount, forKey: .clickCount)
    }
}

public struct TypeActionRequest: Codable, Sendable, Equatable {
    public var text: String
    public var app: String?

    public init(text: String, app: String? = nil) {
        self.text = text
        self.app = app
    }
}

public enum KeyModifier: String, Codable, Sendable, Equatable, Hashable {
    case command
    case shift
    case option
    case control
}

public struct KeyActionRequest: Codable, Sendable, Equatable {
    public var key: String
    public var modifiers: [KeyModifier]
    public var app: String?

    public init(
        key: String,
        modifiers: [KeyModifier] = [],
        app: String? = nil
    ) {
        self.key = key
        self.modifiers = modifiers
        self.app = app
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case key
        case modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        app = try container.decodeIfPresent(String.self, forKey: .app)
        key = try container.decode(String.self, forKey: .key)
        modifiers = try container.decodeIfPresent([KeyModifier].self, forKey: .modifiers) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(app, forKey: .app)
        try container.encode(key, forKey: .key)
        if modifiers.isEmpty == false {
            try container.encode(modifiers, forKey: .modifiers)
        }
    }
}

public struct DragActionRequest: Codable, Sendable, Equatable {
    public var from: Point
    public var to: Point
    public var app: String?

    public init(from: Point, to: Point, app: String? = nil) {
        self.from = from
        self.to = to
        self.app = app
    }
}

public struct ScrollActionRequest: Codable, Sendable, Equatable {
    public var target: SnapshotElementReference
    public var direction: ScrollDirection
    public var pages: Double
    public var app: String?

    public init(
        target: SnapshotElementReference,
        direction: ScrollDirection,
        pages: Double,
        app: String? = nil
    ) {
        self.target = target
        self.direction = direction
        self.pages = pages
        self.app = app
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case snapshotID = "snapshot_id"
        case elementID = "element_id"
        case elementIndex = "element_index"
        case direction
        case pages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try SnapshotElementReference(
            snapshotID: try container.decodeIfPresent(String.self, forKey: .snapshotID),
            elementID: try container.decodeIfPresent(String.self, forKey: .elementID),
            elementIndex: try container.decodeIfPresent(Int.self, forKey: .elementIndex)
        )
        app = try container.decodeIfPresent(String.self, forKey: .app)
        direction = try container.decode(ScrollDirection.self, forKey: .direction)
        pages = try container.decode(Double.self, forKey: .pages)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(app, forKey: .app)
        try container.encodeIfPresent(target.snapshotID, forKey: .snapshotID)
        try container.encodeIfPresent(target.elementID, forKey: .elementID)
        try container.encodeIfPresent(target.elementIndex, forKey: .elementIndex)
        try container.encode(direction, forKey: .direction)
        try container.encode(pages, forKey: .pages)
    }
}

public struct SetValueActionRequest: Codable, Sendable, Equatable {
    public var target: SnapshotElementReference
    public var value: String
    public var app: String?

    public init(target: SnapshotElementReference, value: String, app: String? = nil) {
        self.target = target
        self.value = value
        self.app = app
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case snapshotID = "snapshot_id"
        case elementID = "element_id"
        case elementIndex = "element_index"
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try SnapshotElementReference(
            snapshotID: try container.decodeIfPresent(String.self, forKey: .snapshotID),
            elementID: try container.decodeIfPresent(String.self, forKey: .elementID),
            elementIndex: try container.decodeIfPresent(Int.self, forKey: .elementIndex)
        )
        app = try container.decodeIfPresent(String.self, forKey: .app)
        value = try container.decode(String.self, forKey: .value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(app, forKey: .app)
        try container.encodeIfPresent(target.snapshotID, forKey: .snapshotID)
        try container.encodeIfPresent(target.elementID, forKey: .elementID)
        try container.encodeIfPresent(target.elementIndex, forKey: .elementIndex)
        try container.encode(value, forKey: .value)
    }
}

public struct ElementActionRequest: Codable, Sendable, Equatable {
    public var target: SnapshotElementReference
    public var name: String
    public var app: String?

    public init(target: SnapshotElementReference, name: String, app: String? = nil) {
        self.target = target
        self.name = name
        self.app = app
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case snapshotID = "snapshot_id"
        case elementID = "element_id"
        case elementIndex = "element_index"
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = try SnapshotElementReference(
            snapshotID: try container.decodeIfPresent(String.self, forKey: .snapshotID),
            elementID: try container.decodeIfPresent(String.self, forKey: .elementID),
            elementIndex: try container.decodeIfPresent(Int.self, forKey: .elementIndex)
        )
        app = try container.decodeIfPresent(String.self, forKey: .app)
        name = try container.decode(String.self, forKey: .name)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(app, forKey: .app)
        try container.encodeIfPresent(target.snapshotID, forKey: .snapshotID)
        try container.encodeIfPresent(target.elementID, forKey: .elementID)
        try container.encodeIfPresent(target.elementIndex, forKey: .elementIndex)
        try container.encode(name, forKey: .name)
    }
}
