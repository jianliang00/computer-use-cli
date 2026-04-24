import AgentProtocol
import Foundation
import Darwin

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

public protocol BootstrapStatusChecking: Sendable {
    func currentStatus(configuration: BootstrapAgentConfiguration) async throws -> BootstrapStatus
}

public final class DefaultBootstrapStatusService: BootstrapStatusServicing, @unchecked Sendable {
    private let configuration: BootstrapAgentConfiguration
    private let checker: any BootstrapStatusChecking
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        configuration: BootstrapAgentConfiguration = .guestDefault,
        checker: any BootstrapStatusChecking = MacOSBootstrapStatusChecker(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.checker = checker
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func currentStatus() async throws -> BootstrapStatus {
        let url = URL(fileURLWithPath: configuration.statusFilePath)
        let data = try Data(contentsOf: url)
        return try decoder.decode(BootstrapStatus.self, from: data)
    }

    public func persist(_ status: BootstrapStatus) async throws {
        let url = URL(fileURLWithPath: configuration.statusFilePath)
        let directory = url.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directory.path) == false {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let data = try encoder.encode(status)
        try data.write(to: url, options: .atomic)
    }

    public func refreshStatus() async throws -> BootstrapStatus {
        let status = try await checker.currentStatus(configuration: configuration)
        try await persist(status)
        return status
    }
}

public struct MacOSBootstrapStatusChecker: BootstrapStatusChecking, @unchecked Sendable {
    private let fileManager: FileManager
    private let healthProbeTimeout: TimeInterval

    public init(
        fileManager: FileManager = .default,
        healthProbeTimeout: TimeInterval = 1
    ) {
        self.fileManager = fileManager
        self.healthProbeTimeout = healthProbeTimeout
    }

    public func currentStatus(configuration: BootstrapAgentConfiguration) async throws -> BootstrapStatus {
        let user = consoleUser() ?? NSUserName()
        let sessionReady = user == configuration.expectedUser
        let agentInstalled = fileManager.fileExists(atPath: configuration.sessionAgentBundlePath)
        let agentRunning = await agentHealthIsReachable(
            port: configuration.sessionAgentPort
        )

        return BootstrapStatus(
            bootstrapped: sessionReady && agentInstalled && agentRunning,
            user: user,
            sessionReady: sessionReady,
            agentInstalled: agentInstalled,
            agentRunning: agentRunning,
            agentPort: configuration.sessionAgentPort
        )
    }

    private func consoleUser() -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: "/dev/console"),
              let ownerID = attributes[.ownerAccountID] as? NSNumber,
              let passwd = getpwuid(uid_t(ownerID.intValue)),
              let name = passwd.pointee.pw_name else {
            return nil
        }

        return String(cString: name)
    }

    private func agentHealthIsReachable(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = healthProbeTimeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }
}
