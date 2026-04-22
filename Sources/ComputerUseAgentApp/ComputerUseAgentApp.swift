import AgentProtocol
import ComputerUseAgentCore
import Foundation

public struct SessionAgentHealth: Equatable, Sendable {
    public let configuration: SessionAgentConfiguration
    public let capabilities: AgentCapabilities

    public init(
        configuration: SessionAgentConfiguration,
        capabilities: AgentCapabilities
    ) {
        self.configuration = configuration
        self.capabilities = capabilities
    }
}
