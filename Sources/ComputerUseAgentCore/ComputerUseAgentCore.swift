import AgentProtocol
import Foundation

public enum ComputerUseAgentCoreError: Error, LocalizedError, Equatable, Sendable {
    case notImplemented(String)
    case unsupportedAction(String)

    public var errorDescription: String? {
        switch self {
        case let .notImplemented(capability):
            "\(capability) is not implemented yet"
        case let .unsupportedAction(action):
            "\(action) is not supported"
        }
    }
}

public struct DefaultComputerUseSessionAgent: ComputerUseSessionAgent {
    private let permissionProvider: any PermissionStatusProviding
    private let applicationLister: any RunningApplicationListing
    private let stateCapturer: any StateCapturing
    private let actionPerformer: any ActionPerforming

    public init(
        permissionProvider: any PermissionStatusProviding = MacOSPermissionStatusProvider(),
        applicationLister: any RunningApplicationListing = WorkspaceRunningApplicationLister(),
        stateCapturer: (any StateCapturing)? = nil,
        actionPerformer: any ActionPerforming = MacOSActionPerformer()
    ) {
        self.permissionProvider = permissionProvider
        self.applicationLister = applicationLister
        self.stateCapturer = stateCapturer ?? MacOSStateCapturer(applicationLister: applicationLister)
        self.actionPerformer = actionPerformer
    }

    public func currentPermissions() async throws -> PermissionSnapshot {
        try await permissionProvider.currentPermissions()
    }

    public func runningApplications() async throws -> [RunningApplication] {
        try await applicationLister.runningApplications()
    }

    public func captureState() async throws -> AgentStateSnapshot {
        try await stateCapturer.captureState()
    }

    public func click(_ request: ClickActionRequest) async throws -> ActionReceipt {
        try await actionPerformer.click(request)
    }

    public func type(_ request: TypeActionRequest) async throws -> ActionReceipt {
        try await actionPerformer.type(request)
    }

    public func key(_ request: KeyActionRequest) async throws -> ActionReceipt {
        try await actionPerformer.key(request)
    }

    public func drag(_ request: DragActionRequest) async throws -> ActionReceipt {
        try await actionPerformer.drag(request)
    }

    public func scroll(_ request: ScrollActionRequest) async throws -> ActionReceipt {
        try await actionPerformer.scroll(request)
    }

    public func setValue(_ request: SetValueActionRequest) async throws -> ActionReceipt {
        try await actionPerformer.setValue(request)
    }

    public func perform(_ request: ElementActionRequest) async throws -> ActionReceipt {
        try await actionPerformer.perform(request)
    }
}

public struct SnapshotCachePolicy: Equatable, Sendable {
    public let capacity: Int
    public let timeToLive: TimeInterval

    public init(
        capacity: Int = 8,
        timeToLive: TimeInterval = 60
    ) {
        self.capacity = capacity
        self.timeToLive = timeToLive
    }
}

public struct AgentCapabilities: Equatable, Sendable {
    public let supportsAccessibility: Bool
    public let supportsScreenCapture: Bool
    public let supportsInputSynthesis: Bool

    public init(
        supportsAccessibility: Bool,
        supportsScreenCapture: Bool,
        supportsInputSynthesis: Bool
    ) {
        self.supportsAccessibility = supportsAccessibility
        self.supportsScreenCapture = supportsScreenCapture
        self.supportsInputSynthesis = supportsInputSynthesis
    }
}
