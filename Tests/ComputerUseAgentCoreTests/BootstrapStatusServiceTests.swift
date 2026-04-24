import BootstrapAgent
import Foundation
import Testing

@Test
func bootstrapStatusServiceRefreshesAndPersistsStatus() async throws {
    let directory = try temporaryDirectory()
    let statusFile = directory
        .appending(path: "var/run/computer-use/bootstrap-status.json")
    let expectedStatus = BootstrapStatus(
        bootstrapped: true,
        user: "admin",
        sessionReady: true,
        agentInstalled: true,
        agentRunning: true,
        agentPort: 7777
    )
    let service = DefaultBootstrapStatusService(
        configuration: BootstrapAgentConfiguration(
            executablePath: "/usr/local/libexec/computer-use/bootstrap-agent",
            launchDaemonLabel: "io.github.jianliang00.computer-use.bootstrap",
            statusFilePath: statusFile.path,
            expectedUser: "admin",
            sessionAgentBundlePath: "/Applications/ComputerUseAgent.app",
            sessionAgentPort: 7777,
            logFilePath: "/var/log/computer-use-bootstrap.log"
        ),
        checker: StubBootstrapStatusChecker(status: expectedStatus)
    )

    let refreshed = try await service.refreshStatus()
    #expect(refreshed == expectedStatus)

    let persisted = try await service.currentStatus()
    #expect(persisted == expectedStatus)
}

@Test
func bootstrapAgentDefaultsMatchTechnicalPlan() {
    let configuration = BootstrapAgentConfiguration.guestDefault

    #expect(configuration.executablePath == "/usr/local/libexec/computer-use/bootstrap-agent")
    #expect(configuration.launchDaemonLabel == "io.github.jianliang00.computer-use.bootstrap")
    #expect(configuration.statusFilePath == "/var/run/computer-use/bootstrap-status.json")
    #expect(configuration.expectedUser == "admin")
    #expect(configuration.sessionAgentBundlePath == "/Applications/ComputerUseAgent.app")
    #expect(configuration.sessionAgentPort == 7777)
}

private struct StubBootstrapStatusChecker: BootstrapStatusChecking {
    let status: BootstrapStatus

    func currentStatus(configuration: BootstrapAgentConfiguration) async throws -> BootstrapStatus {
        status
    }
}

private func temporaryDirectory() throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}
