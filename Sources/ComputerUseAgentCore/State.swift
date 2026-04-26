import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

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
    public var index: Int?
    public var id: String
    public var role: String
    public var title: String?
    public var value: String?
    public var frame: Rect?
    public var actions: [String]
    public var children: [AccessibilityNode]

    public init(
        index: Int? = nil,
        id: String,
        role: String,
        title: String? = nil,
        value: String? = nil,
        frame: Rect? = nil,
        actions: [String] = [],
        children: [AccessibilityNode] = []
    ) {
        self.index = index
        self.id = id
        self.role = role
        self.title = title
        self.value = value
        self.frame = frame
        self.actions = actions
        self.children = children
    }
}

public struct AgentStateSnapshot: Codable, Equatable, Sendable {
    public var snapshotID: String
    public var screenshot: ScreenshotFrame
    public var accessibilityRoot: AccessibilityNode
    public var applications: [RunningApplication]
    public var focusedElementID: String?

    public init(
        snapshotID: String,
        screenshot: ScreenshotFrame,
        accessibilityRoot: AccessibilityNode,
        applications: [RunningApplication],
        focusedElementID: String? = nil
    ) {
        self.snapshotID = snapshotID
        self.screenshot = screenshot
        self.accessibilityRoot = accessibilityRoot
        self.applications = applications
        self.focusedElementID = focusedElementID
    }
}

public protocol StateCapturing: Sendable {
    func captureState(bundleIdentifier: String?) async throws -> AgentStateSnapshot
}

public extension StateCapturing {
    func captureState() async throws -> AgentStateSnapshot {
        try await captureState(bundleIdentifier: nil)
    }
}

public struct MacOSStateCapturer: StateCapturing {
    private let applicationLister: any RunningApplicationListing
    private let elementCache: MacOSSnapshotElementCache?
    private let maxAccessibilityDepth: Int
    private let maxAccessibilityNodes: Int

    public init(
        applicationLister: any RunningApplicationListing = WorkspaceRunningApplicationLister(),
        elementCache: MacOSSnapshotElementCache? = nil,
        maxAccessibilityDepth: Int = 8,
        maxAccessibilityNodes: Int = 400
    ) {
        self.applicationLister = applicationLister
        self.elementCache = elementCache
        self.maxAccessibilityDepth = maxAccessibilityDepth
        self.maxAccessibilityNodes = maxAccessibilityNodes
    }

    public func captureState(bundleIdentifier: String? = nil) async throws -> AgentStateSnapshot {
        let snapshotID = UUID().uuidString
        let applications = try await applicationLister.runningApplications()
        let screenshot = try await captureScreenshot()
        let root = captureAccessibilityRoot(
            snapshotID: snapshotID,
            targetApplication: selectedApplication(
                applications: applications,
                bundleIdentifier: bundleIdentifier
            ),
            applications: applications
        )

        return AgentStateSnapshot(
            snapshotID: snapshotID,
            screenshot: screenshot,
            accessibilityRoot: root.node,
            applications: applications,
            focusedElementID: root.focusedElementID
        )
    }

    private func captureScreenshot() async throws -> ScreenshotFrame {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw ComputerUseAgentCoreError.notImplemented("screen capture")
        }

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = true

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw ComputerUseAgentCoreError.notImplemented("PNG screenshot encoding")
        }

        return ScreenshotFrame(
            encoding: .png,
            size: Size(width: Double(image.width), height: Double(image.height)),
            bytes: Array(data)
        )
    }

    private func captureAccessibilityRoot(
        snapshotID: String,
        targetApplication: RunningApplication?,
        applications: [RunningApplication]
    ) -> (node: AccessibilityNode, focusedElementID: String?) {
        let pid = targetApplication?.processIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
            ?? applications.first(where: \.isFrontmost)?.processIdentifier
            ?? applications.first?.processIdentifier

        guard let pid else {
            return (
                AccessibilityNode(
                id: "ax-root",
                role: "AXApplication",
                title: "No frontmost application"
                ),
                nil
            )
        }

        var nextID = 0
        var nextIndex = 0
        var remainingNodes = maxAccessibilityNodes
        var elements: [String: AXUIElement] = [:]
        var elementIDsByIndex: [Int: String] = [:]
        let element = AXUIElementCreateApplication(pid)
        let focusedElement = focusedElement(in: element)
        var focusedElementID: String?

        func buildNode(
            from element: AXUIElement,
            depth: Int
        ) -> AccessibilityNode {
            nextID += 1
            let index = nextIndex
            nextIndex += 1
            remainingNodes -= 1
            let id = "ax-\(nextID)"
            elements[id] = element
            elementIDsByIndex[index] = id
            if let focusedElement, CFEqual(element, focusedElement) {
                focusedElementID = id
            }

            let childElements = depth < maxAccessibilityDepth && remainingNodes > 0
                ? accessibilityChildren(of: element)
                : []
            var children: [AccessibilityNode] = []
            for child in childElements where remainingNodes > 0 {
                children.append(buildNode(from: child, depth: depth + 1))
            }

            return AccessibilityNode(
                index: index,
                id: id,
                role: stringAttribute(kAXRoleAttribute, from: element) ?? "AXUnknown",
                title: stringAttribute(kAXTitleAttribute, from: element),
                value: valueDescription(kAXValueAttribute, from: element),
                frame: frame(from: element),
                actions: actionNames(of: element),
                children: children
            )
        }

        let root = buildNode(from: element, depth: 0)
        elementCache?.store(
            snapshotID: snapshotID,
            elements: elements,
            elementIDsByIndex: elementIDsByIndex,
            appBundleIdentifier: targetApplication?.bundleIdentifier
        )
        return (root, focusedElementID)
    }

    private func focusedElement(in applicationElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }

        guard let value else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let names else {
            return []
        }

        return (names as? [String]) ?? []
    }

    private func selectedApplication(
        applications: [RunningApplication],
        bundleIdentifier: String?
    ) -> RunningApplication? {
        if let bundleIdentifier {
            return applications.first { $0.bundleIdentifier == bundleIdentifier }
        }

        return applications.first(where: \.isFrontmost) ?? applications.first
    }

    private func accessibilityChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }

        return (value as? [AXUIElement]) ?? []
    }

    private func stringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private func valueDescription(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else {
            return nil
        }

        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        return nil
    }

    private func frame(from element: AXUIElement) -> Rect? {
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
}
