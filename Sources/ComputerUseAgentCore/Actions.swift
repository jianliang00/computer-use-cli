import ApplicationServices
import CoreGraphics
import Foundation

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
    public var location: Point?
    public var snapshotID: String?
    public var elementID: String?
    public var elementIndex: Int?
    public var appBundleIdentifier: String?
    public var button: MouseButton
    public var clickCount: Int

    public init(
        location: Point,
        button: MouseButton = .left,
        clickCount: Int = 1
    ) {
        self.location = location
        self.snapshotID = nil
        self.elementID = nil
        self.elementIndex = nil
        self.appBundleIdentifier = nil
        self.button = button
        self.clickCount = clickCount
    }

    public init(
        snapshotID: String,
        elementID: String,
        button: MouseButton = .left,
        clickCount: Int = 1,
        appBundleIdentifier: String? = nil
    ) {
        self.location = nil
        self.snapshotID = snapshotID
        self.elementID = elementID
        self.elementIndex = nil
        self.appBundleIdentifier = appBundleIdentifier
        self.button = button
        self.clickCount = clickCount
    }

    public init(
        snapshotID: String? = nil,
        elementIndex: Int,
        button: MouseButton = .left,
        clickCount: Int = 1,
        appBundleIdentifier: String? = nil
    ) {
        self.location = nil
        self.snapshotID = snapshotID
        self.elementID = nil
        self.elementIndex = elementIndex
        self.appBundleIdentifier = appBundleIdentifier
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
    public var snapshotID: String?
    public var elementID: String?
    public var elementIndex: Int?
    public var appBundleIdentifier: String?

    public init(
        deltaX: Double,
        deltaY: Double,
        snapshotID: String? = nil,
        elementID: String? = nil,
        elementIndex: Int? = nil,
        appBundleIdentifier: String? = nil
    ) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.snapshotID = snapshotID
        self.elementID = elementID
        self.elementIndex = elementIndex
        self.appBundleIdentifier = appBundleIdentifier
    }
}

public struct SetValueActionRequest: Codable, Equatable, Sendable {
    public var snapshotID: String?
    public var elementID: String?
    public var elementIndex: Int?
    public var appBundleIdentifier: String?
    public var value: String

    public init(
        elementID: String,
        value: String,
        snapshotID: String? = nil,
        appBundleIdentifier: String? = nil
    ) {
        self.snapshotID = snapshotID
        self.elementID = elementID
        self.elementIndex = nil
        self.appBundleIdentifier = appBundleIdentifier
        self.value = value
    }

    public init(
        elementIndex: Int,
        value: String,
        snapshotID: String? = nil,
        appBundleIdentifier: String? = nil
    ) {
        self.snapshotID = snapshotID
        self.elementID = nil
        self.elementIndex = elementIndex
        self.appBundleIdentifier = appBundleIdentifier
        self.value = value
    }
}

public struct ElementActionRequest: Codable, Equatable, Sendable {
    public var snapshotID: String?
    public var elementID: String?
    public var elementIndex: Int?
    public var appBundleIdentifier: String?
    public var actionName: String

    public init(
        elementID: String,
        actionName: String,
        snapshotID: String? = nil,
        appBundleIdentifier: String? = nil
    ) {
        self.snapshotID = snapshotID
        self.elementID = elementID
        self.elementIndex = nil
        self.appBundleIdentifier = appBundleIdentifier
        self.actionName = actionName
    }

    public init(
        elementIndex: Int,
        actionName: String,
        snapshotID: String? = nil,
        appBundleIdentifier: String? = nil
    ) {
        self.snapshotID = snapshotID
        self.elementID = nil
        self.elementIndex = elementIndex
        self.appBundleIdentifier = appBundleIdentifier
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

public struct MacOSActionPerformer: ActionPerforming {
    private let elementCache: MacOSSnapshotElementCache?

    public init(elementCache: MacOSSnapshotElementCache? = nil) {
        self.elementCache = elementCache
    }

    public func click(_ request: ClickActionRequest) async throws -> ActionReceipt {
        let request = try resolvedClickRequest(request)
        guard let requestLocation = request.location else {
            throw ComputerUseAgentCoreError.unsupportedAction("click")
        }

        let location = CGPoint(x: requestLocation.x, y: requestLocation.y)
        let button = cgMouseButton(request.button)
        let downType = mouseDownType(request.button)
        let upType = mouseUpType(request.button)

        for _ in 0..<max(request.clickCount, 1) {
            postMouse(type: downType, location: location, button: button)
            postMouse(type: upType, location: location, button: button)
        }

        return ActionReceipt(accepted: true)
    }

    public func type(_ request: TypeActionRequest) async throws -> ActionReceipt {
        for codeUnit in request.text.utf16 {
            var character = codeUnit
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                throw ComputerUseAgentCoreError.unsupportedAction("type")
            }

            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
            down.post(tap: .cghidEventTap)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
            up.post(tap: .cghidEventTap)
        }

        return ActionReceipt(accepted: true)
    }

    public func key(_ request: KeyActionRequest) async throws -> ActionReceipt {
        guard let keyCode = keyCode(for: request.key),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw ComputerUseAgentCoreError.unsupportedAction("key \(request.key)")
        }

        let flags = eventFlags(for: request.modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return ActionReceipt(accepted: true)
    }

    public func drag(_ request: DragActionRequest) async throws -> ActionReceipt {
        let start = CGPoint(x: request.start.x, y: request.start.y)
        let end = CGPoint(x: request.end.x, y: request.end.y)

        postMouse(type: .mouseMoved, location: start, button: .left)
        postMouse(type: .leftMouseDown, location: start, button: .left)
        postMouse(type: .leftMouseDragged, location: end, button: .left)
        postMouse(type: .leftMouseUp, location: end, button: .left)
        return ActionReceipt(accepted: true)
    }

    public func scroll(_ request: ScrollActionRequest) async throws -> ActionReceipt {
        if request.elementID != nil || request.elementIndex != nil {
            _ = try cachedElement(
                snapshotID: request.snapshotID,
                elementID: request.elementID,
                elementIndex: request.elementIndex,
                appBundleIdentifier: request.appBundleIdentifier
            )
        }

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(request.deltaY),
            wheel2: Int32(request.deltaX),
            wheel3: 0
        ) else {
            throw ComputerUseAgentCoreError.unsupportedAction("scroll")
        }

        event.post(tap: .cghidEventTap)
        return ActionReceipt(accepted: true)
    }

    public func setValue(_ request: SetValueActionRequest) async throws -> ActionReceipt {
        let element = try cachedElement(
            snapshotID: request.snapshotID,
            elementID: request.elementID,
            elementIndex: request.elementIndex,
            appBundleIdentifier: request.appBundleIdentifier
        )
        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            request.value as CFTypeRef
        )
        guard result == .success else {
            throw ComputerUseAgentCoreError.unsupportedAction("set-value")
        }

        return ActionReceipt(accepted: true)
    }

    public func perform(_ request: ElementActionRequest) async throws -> ActionReceipt {
        let element = try cachedElement(
            snapshotID: request.snapshotID,
            elementID: request.elementID,
            elementIndex: request.elementIndex,
            appBundleIdentifier: request.appBundleIdentifier
        )
        let result = AXUIElementPerformAction(
            element,
            request.actionName as CFString
        )
        guard result == .success else {
            throw ComputerUseAgentCoreError.unsupportedAction(request.actionName)
        }

        return ActionReceipt(accepted: true)
    }

    private func postMouse(
        type: CGEventType,
        location: CGPoint,
        button: CGMouseButton
    ) {
        CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
    }

    private func cgMouseButton(_ button: MouseButton) -> CGMouseButton {
        switch button {
        case .left:
            .left
        case .right:
            .right
        case .center:
            .center
        }
    }

    private func mouseDownType(_ button: MouseButton) -> CGEventType {
        switch button {
        case .left:
            .leftMouseDown
        case .right:
            .rightMouseDown
        case .center:
            .otherMouseDown
        }
    }

    private func mouseUpType(_ button: MouseButton) -> CGEventType {
        switch button {
        case .left:
            .leftMouseUp
        case .right:
            .rightMouseUp
        case .center:
            .otherMouseUp
        }
    }

    private func eventFlags(for modifiers: [KeyModifier]) -> CGEventFlags {
        var flags = CGEventFlags()
        for modifier in modifiers {
            switch modifier {
            case .command:
                flags.insert(.maskCommand)
            case .shift:
                flags.insert(.maskShift)
            case .option:
                flags.insert(.maskAlternate)
            case .control:
                flags.insert(.maskControl)
            }
        }
        return flags
    }

    private func keyCode(for key: String) -> CGKeyCode? {
        let normalized = key.lowercased()
        if let code = specialKeyCodes[normalized] {
            return code
        }

        if normalized.count == 1, let character = normalized.first {
            return characterKeyCodes[character]
        }

        return nil
    }

    private func cachedElement(
        snapshotID: String?,
        elementID: String?,
        elementIndex: Int?,
        appBundleIdentifier: String?
    ) throws -> AXUIElement {
        guard let elementCache else {
            throw SnapshotCacheError.snapshotExpired(snapshotID ?? "")
        }

        return try elementCache.element(
            snapshotID: snapshotID,
            elementID: elementID,
            elementIndex: elementIndex,
            appBundleIdentifier: appBundleIdentifier
        )
    }

    private func resolvedClickRequest(_ request: ClickActionRequest) throws -> ClickActionRequest {
        if request.location != nil {
            return request
        }

        guard request.elementID != nil || request.elementIndex != nil else {
            throw ComputerUseAgentCoreError.unsupportedAction("click")
        }

        let element = try cachedElement(
            snapshotID: request.snapshotID,
            elementID: request.elementID,
            elementIndex: request.elementIndex,
            appBundleIdentifier: request.appBundleIdentifier
        )
        guard let frame = frame(of: element) else {
            throw ComputerUseAgentCoreError.unsupportedAction("element click")
        }

        return ClickActionRequest(
            location: Point(
                x: frame.origin.x + frame.size.width / 2,
                y: frame.origin.y + frame.size.height / 2
            ),
            button: request.button,
            clickCount: request.clickCount
        )
    }

    private func frame(of element: AXUIElement) -> Rect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &origin),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return nil
        }

        return Rect(
            origin: Point(x: origin.x, y: origin.y),
            size: Size(width: size.width, height: size.height)
        )
    }

    private var specialKeyCodes: [String: CGKeyCode] {
        [
            "return": 36,
            "enter": 36,
            "tab": 48,
            "space": 49,
            "escape": 53,
            "esc": 53,
            "delete": 51,
            "backspace": 51,
            "forwarddelete": 117,
            "left": 123,
            "right": 124,
            "down": 125,
            "up": 126,
        ]
    }

    private var characterKeyCodes: [Character: CGKeyCode] {
        [
            "a": 0,
            "s": 1,
            "d": 2,
            "f": 3,
            "h": 4,
            "g": 5,
            "z": 6,
            "x": 7,
            "c": 8,
            "v": 9,
            "b": 11,
            "q": 12,
            "w": 13,
            "e": 14,
            "r": 15,
            "y": 16,
            "t": 17,
            "1": 18,
            "2": 19,
            "3": 20,
            "4": 21,
            "6": 22,
            "5": 23,
            "=": 24,
            "9": 25,
            "7": 26,
            "-": 27,
            "8": 28,
            "0": 29,
            "]": 30,
            "o": 31,
            "u": 32,
            "[": 33,
            "i": 34,
            "p": 35,
            "l": 37,
            "j": 38,
            "'": 39,
            "k": 40,
            ";": 41,
            "\\": 42,
            ",": 43,
            "/": 44,
            "n": 45,
            "m": 46,
            ".": 47,
            "`": 50,
        ]
    }
}
