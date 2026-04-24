import ApplicationServices
import CoreGraphics

public enum AgentPermission: String, Codable, CaseIterable, Sendable {
    case accessibility
    case screenRecording
}

public enum PermissionGrant: String, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
}

public struct PermissionSnapshot: Codable, Equatable, Sendable {
    public var accessibility: PermissionGrant
    public var screenRecording: PermissionGrant

    public init(
        accessibility: PermissionGrant,
        screenRecording: PermissionGrant
    ) {
        self.accessibility = accessibility
        self.screenRecording = screenRecording
    }

    public var isReadyForAutomation: Bool {
        accessibility == .authorized && screenRecording == .authorized
    }

    public var missingPermissions: [AgentPermission] {
        var missing: [AgentPermission] = []

        if accessibility != .authorized {
            missing.append(.accessibility)
        }

        if screenRecording != .authorized {
            missing.append(.screenRecording)
        }

        return missing
    }
}

public protocol PermissionStatusProviding: Sendable {
    func currentPermissions() async throws -> PermissionSnapshot
}

public struct MacOSPermissionStatusProvider: PermissionStatusProviding {
    public init() {}

    public func currentPermissions() async throws -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: AXIsProcessTrusted() ? .authorized : .denied,
            screenRecording: CGPreflightScreenCaptureAccess() ? .authorized : .denied
        )
    }
}
