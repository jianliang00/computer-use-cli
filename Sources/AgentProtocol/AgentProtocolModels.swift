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
