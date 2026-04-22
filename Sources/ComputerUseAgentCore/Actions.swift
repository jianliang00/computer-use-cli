public enum MouseButton: String, Codable, Sendable {
    case left
    case right
    case center
}

public enum KeyModifier: String, Codable, CaseIterable, Sendable {
    case command
    case shift
    case option
    case control
}

public struct ClickActionRequest: Codable, Equatable, Sendable {
    public var location: Point
    public var button: MouseButton
    public var clickCount: Int

    public init(
        location: Point,
        button: MouseButton = .left,
        clickCount: Int = 1
    ) {
        self.location = location
        self.button = button
        self.clickCount = clickCount
    }
}

public struct TypeActionRequest: Codable, Equatable, Sendable {
    public var text: String

    public init(text: String) {
        self.text = text
    }
}

public struct KeyActionRequest: Codable, Equatable, Sendable {
    public var key: String
    public var modifiers: [KeyModifier]

    public init(
        key: String,
        modifiers: [KeyModifier] = []
    ) {
        self.key = key
        self.modifiers = modifiers
    }
}

public struct DragActionRequest: Codable, Equatable, Sendable {
    public var start: Point
    public var end: Point

    public init(start: Point, end: Point) {
        self.start = start
        self.end = end
    }
}

public struct ScrollActionRequest: Codable, Equatable, Sendable {
    public var deltaX: Double
    public var deltaY: Double

    public init(deltaX: Double, deltaY: Double) {
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

public struct SetValueActionRequest: Codable, Equatable, Sendable {
    public var elementID: String
    public var value: String

    public init(elementID: String, value: String) {
        self.elementID = elementID
        self.value = value
    }
}

public struct ElementActionRequest: Codable, Equatable, Sendable {
    public var elementID: String
    public var actionName: String

    public init(elementID: String, actionName: String) {
        self.elementID = elementID
        self.actionName = actionName
    }
}

public struct ActionReceipt: Codable, Equatable, Sendable {
    public var accepted: Bool
    public var message: String?

    public init(accepted: Bool, message: String? = nil) {
        self.accepted = accepted
        self.message = message
    }
}

public protocol ActionPerforming: Sendable {
    func click(_ request: ClickActionRequest) async throws -> ActionReceipt
    func type(_ request: TypeActionRequest) async throws -> ActionReceipt
    func key(_ request: KeyActionRequest) async throws -> ActionReceipt
    func drag(_ request: DragActionRequest) async throws -> ActionReceipt
    func scroll(_ request: ScrollActionRequest) async throws -> ActionReceipt
    func setValue(_ request: SetValueActionRequest) async throws -> ActionReceipt
    func perform(_ request: ElementActionRequest) async throws -> ActionReceipt
}
