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

public struct StateRequest: Codable, Sendable, Equatable {
    public var bundleID: String?

    public init(bundleID: String? = nil) {
        self.bundleID = bundleID
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
    }
}

public struct StateResponse: Codable, Sendable, Equatable {
    public var snapshotID: String
    public var app: ApplicationDescriptor
    public var window: WindowDescriptor?
    public var screenshot: ScreenshotPayload
    public var axTree: AXTree

    public init(
        snapshotID: String,
        app: ApplicationDescriptor,
        window: WindowDescriptor?,
        screenshot: ScreenshotPayload,
        axTree: AXTree
    ) {
        self.snapshotID = snapshotID
        self.app = app
        self.window = window
        self.screenshot = screenshot
        self.axTree = axTree
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case app
        case window
        case screenshot
        case axTree = "ax_tree"
    }
}

public struct ActionResponse: Codable, Sendable, Equatable {
    public var ok: Bool

    public init(ok: Bool = true) {
        self.ok = ok
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

    public init(target: Target, button: MouseButton = .left, clickCount: Int = 1) {
        self.target = target
        self.button = button
        self.clickCount = clickCount
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case snapshotID = "snapshot_id"
        case elementID = "element_id"
        case button
        case clickCount = "click_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decodeIfPresent(Double.self, forKey: .x)
        let y = try container.decodeIfPresent(Double.self, forKey: .y)
        let snapshotID = try container.decodeIfPresent(String.self, forKey: .snapshotID)
        let elementID = try container.decodeIfPresent(String.self, forKey: .elementID)

        switch (x, y, snapshotID, elementID) {
        case let (.some(x), .some(y), nil, nil):
            target = .coordinates(Point(x: x, y: y))
        case let (nil, nil, .some(snapshotID), .some(elementID)):
            target = .element(SnapshotElementReference(snapshotID: snapshotID, elementID: elementID))
        default:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "ClickActionRequest must include either x/y or snapshot_id/element_id."
                )
            )
        }

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
            try container.encode(reference.snapshotID, forKey: .snapshotID)
            try container.encode(reference.elementID, forKey: .elementID)
        }

        try container.encode(button, forKey: .button)
        try container.encode(clickCount, forKey: .clickCount)
    }
}

public struct TypeActionRequest: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct KeyActionRequest: Codable, Sendable, Equatable {
    public var key: String

    public init(key: String) {
        self.key = key
    }
}

public struct DragActionRequest: Codable, Sendable, Equatable {
    public var from: Point
    public var to: Point

    public init(from: Point, to: Point) {
        self.from = from
        self.to = to
    }
}

public struct ScrollActionRequest: Codable, Sendable, Equatable {
    public var target: SnapshotElementReference
    public var direction: ScrollDirection
    public var pages: Int

    public init(target: SnapshotElementReference, direction: ScrollDirection, pages: Int) {
        self.target = target
        self.direction = direction
        self.pages = pages
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case elementID = "element_id"
        case direction
        case pages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = SnapshotElementReference(
            snapshotID: try container.decode(String.self, forKey: .snapshotID),
            elementID: try container.decode(String.self, forKey: .elementID)
        )
        direction = try container.decode(ScrollDirection.self, forKey: .direction)
        pages = try container.decode(Int.self, forKey: .pages)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target.snapshotID, forKey: .snapshotID)
        try container.encode(target.elementID, forKey: .elementID)
        try container.encode(direction, forKey: .direction)
        try container.encode(pages, forKey: .pages)
    }
}

public struct SetValueActionRequest: Codable, Sendable, Equatable {
    public var target: SnapshotElementReference
    public var value: String

    public init(target: SnapshotElementReference, value: String) {
        self.target = target
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case elementID = "element_id"
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = SnapshotElementReference(
            snapshotID: try container.decode(String.self, forKey: .snapshotID),
            elementID: try container.decode(String.self, forKey: .elementID)
        )
        value = try container.decode(String.self, forKey: .value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target.snapshotID, forKey: .snapshotID)
        try container.encode(target.elementID, forKey: .elementID)
        try container.encode(value, forKey: .value)
    }
}

public struct ElementActionRequest: Codable, Sendable, Equatable {
    public var target: SnapshotElementReference
    public var name: String

    public init(target: SnapshotElementReference, name: String) {
        self.target = target
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case elementID = "element_id"
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        target = SnapshotElementReference(
            snapshotID: try container.decode(String.self, forKey: .snapshotID),
            elementID: try container.decode(String.self, forKey: .elementID)
        )
        name = try container.decode(String.self, forKey: .name)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target.snapshotID, forKey: .snapshotID)
        try container.encode(target.elementID, forKey: .elementID)
        try container.encode(name, forKey: .name)
    }
}
