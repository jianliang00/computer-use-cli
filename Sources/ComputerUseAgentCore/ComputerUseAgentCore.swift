import AgentProtocol
import Foundation

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
