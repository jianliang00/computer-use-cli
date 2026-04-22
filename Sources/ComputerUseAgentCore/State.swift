public enum ScreenshotEncoding: String, Codable, Sendable {
    case png
}

public struct ScreenshotFrame: Codable, Equatable, Sendable {
    public var encoding: ScreenshotEncoding
    public var size: Size
    public var bytes: [UInt8]

    public init(
        encoding: ScreenshotEncoding,
        size: Size,
        bytes: [UInt8]
    ) {
        self.encoding = encoding
        self.size = size
        self.bytes = bytes
    }
}

public struct AccessibilityNode: Codable, Equatable, Sendable {
    public var id: String
    public var role: String
    public var title: String?
    public var value: String?
    public var frame: Rect?
    public var children: [AccessibilityNode]

    public init(
        id: String,
        role: String,
        title: String? = nil,
        value: String? = nil,
        frame: Rect? = nil,
        children: [AccessibilityNode] = []
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.value = value
        self.frame = frame
        self.children = children
    }
}

public struct AgentStateSnapshot: Codable, Equatable, Sendable {
    public var snapshotID: String
    public var screenshot: ScreenshotFrame
    public var accessibilityRoot: AccessibilityNode
    public var applications: [RunningApplication]

    public init(
        snapshotID: String,
        screenshot: ScreenshotFrame,
        accessibilityRoot: AccessibilityNode,
        applications: [RunningApplication]
    ) {
        self.snapshotID = snapshotID
        self.screenshot = screenshot
        self.accessibilityRoot = accessibilityRoot
        self.applications = applications
    }
}

public protocol StateCapturing: Sendable {
    func captureState() async throws -> AgentStateSnapshot
}
