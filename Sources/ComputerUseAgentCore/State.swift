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

public struct MacOSStateCapturer: StateCapturing {
    private let applicationLister: any RunningApplicationListing
    private let maxAccessibilityDepth: Int
    private let maxAccessibilityNodes: Int

    public init(
        applicationLister: any RunningApplicationListing = WorkspaceRunningApplicationLister(),
        maxAccessibilityDepth: Int = 8,
        maxAccessibilityNodes: Int = 400
    ) {
        self.applicationLister = applicationLister
        self.maxAccessibilityDepth = maxAccessibilityDepth
        self.maxAccessibilityNodes = maxAccessibilityNodes
    }

    public func captureState() async throws -> AgentStateSnapshot {
        let applications = try await applicationLister.runningApplications()
        let screenshot = try await captureScreenshot()
        let root = captureAccessibilityRoot(
            applications: applications
        )

        return AgentStateSnapshot(
            snapshotID: UUID().uuidString,
            screenshot: screenshot,
            accessibilityRoot: root,
            applications: applications
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
        applications: [RunningApplication]
    ) -> AccessibilityNode {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            ?? applications.first(where: \.isFrontmost)?.processIdentifier
            ?? applications.first?.processIdentifier

        guard let pid else {
            return AccessibilityNode(
                id: "ax-root",
                role: "AXApplication",
                title: "No frontmost application"
            )
        }

        var nextID = 0
        var remainingNodes = maxAccessibilityNodes
        let element = AXUIElementCreateApplication(pid)

        func buildNode(
            from element: AXUIElement,
            depth: Int
        ) -> AccessibilityNode {
            nextID += 1
            remainingNodes -= 1
            let id = "ax-\(nextID)"

            let childElements = depth < maxAccessibilityDepth && remainingNodes > 0
                ? accessibilityChildren(of: element)
                : []
            var children: [AccessibilityNode] = []
            for child in childElements where remainingNodes > 0 {
                children.append(buildNode(from: child, depth: depth + 1))
            }

            return AccessibilityNode(
                id: id,
                role: stringAttribute(kAXRoleAttribute, from: element) ?? "AXUnknown",
                title: stringAttribute(kAXTitleAttribute, from: element),
                value: valueDescription(kAXValueAttribute, from: element),
                frame: frame(from: element),
                children: children
            )
        }

        return buildNode(from: element, depth: 0)
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
