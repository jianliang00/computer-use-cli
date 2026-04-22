import Foundation

public struct Point: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Rect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct SnapshotElementReference: Codable, Sendable, Equatable {
    public var snapshotID: String
    public var elementID: String

    public init(snapshotID: String, elementID: String) {
        self.snapshotID = snapshotID
        self.elementID = elementID
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case elementID = "element_id"
    }
}

public struct ApplicationDescriptor: Codable, Sendable, Equatable {
    public var bundleID: String
    public var name: String
    public var pid: Int

    public init(bundleID: String, name: String, pid: Int) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case name
        case pid
    }
}

public struct RunningApplication: Codable, Sendable, Equatable {
    public var bundleID: String
    public var name: String
    public var pid: Int
    public var isFrontmost: Bool

    public init(bundleID: String, name: String, pid: Int, isFrontmost: Bool) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
        self.isFrontmost = isFrontmost
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case name
        case pid
        case isFrontmost = "is_frontmost"
    }
}

public struct WindowDescriptor: Codable, Sendable, Equatable {
    public var title: String?
    public var bounds: Rect

    public init(title: String? = nil, bounds: Rect) {
        self.title = title
        self.bounds = bounds
    }
}

public struct ScreenshotPayload: Codable, Sendable, Equatable {
    public var mimeType: String
    public var base64: String

    public init(mimeType: String, base64: String) {
        self.mimeType = mimeType
        self.base64 = base64
    }

    private enum CodingKeys: String, CodingKey {
        case mimeType = "mime_type"
        case base64
    }
}

public struct AXTree: Codable, Sendable, Equatable {
    public var rootID: String
    public var nodes: [AXNode]

    public init(rootID: String, nodes: [AXNode]) {
        self.rootID = rootID
        self.nodes = nodes
    }

    private enum CodingKeys: String, CodingKey {
        case rootID = "root_id"
        case nodes
    }
}

public struct AXNode: Codable, Sendable, Equatable {
    public var id: String
    public var role: String
    public var title: String?
    public var value: String?
    public var description: String?
    public var bounds: Rect?
    public var children: [String]
    public var actions: [String]

    public init(
        id: String,
        role: String,
        title: String? = nil,
        value: String? = nil,
        description: String? = nil,
        bounds: Rect? = nil,
        children: [String] = [],
        actions: [String] = []
    ) {
        self.id = id
        self.role = role
        self.title = title
        self.value = value
        self.description = description
        self.bounds = bounds
        self.children = children
        self.actions = actions
    }
}

public enum MouseButton: String, Codable, Sendable, Equatable {
    case left
    case right
    case center
}

public enum ScrollDirection: String, Codable, Sendable, Equatable {
    case up
    case down
    case left
    case right
}
