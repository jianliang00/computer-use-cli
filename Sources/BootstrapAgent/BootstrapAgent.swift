import AgentProtocol
import Foundation

public struct BootstrapDiagnostics: Equatable, Sendable {
    public let health: HealthResponse
    public let permissions: PermissionsResponse

    public init(
        health: HealthResponse,
        permissions: PermissionsResponse
    ) {
        self.health = health
        self.permissions = permissions
    }
}
