public struct BootstrapStatus: Codable, Equatable, Sendable {
    public var bootstrapped: Bool
    public var user: String
    public var sessionReady: Bool
    public var agentInstalled: Bool
    public var agentRunning: Bool
    public var agentPort: Int?

    public init(
        bootstrapped: Bool,
        user: String,
        sessionReady: Bool,
        agentInstalled: Bool,
        agentRunning: Bool,
        agentPort: Int?
    ) {
        self.bootstrapped = bootstrapped
        self.user = user
        self.sessionReady = sessionReady
        self.agentInstalled = agentInstalled
        self.agentRunning = agentRunning
        self.agentPort = agentPort
    }
}

public protocol BootstrapStatusProviding: Sendable {
    func currentStatus() async throws -> BootstrapStatus
}

public protocol BootstrapStatusPersisting: Sendable {
    func persist(_ status: BootstrapStatus) async throws
}

public protocol BootstrapStatusServicing: BootstrapStatusProviding, BootstrapStatusPersisting {
    func refreshStatus() async throws -> BootstrapStatus
}
