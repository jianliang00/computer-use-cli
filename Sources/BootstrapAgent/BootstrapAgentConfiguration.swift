public struct BootstrapAgentConfiguration: Codable, Equatable, Sendable {
    public var executablePath: String
    public var launchDaemonLabel: String
    public var statusFilePath: String
    public var expectedUser: String
    public var sessionAgentBundlePath: String
    public var sessionAgentPort: Int
    public var logFilePath: String

    public init(
        executablePath: String,
        launchDaemonLabel: String,
        statusFilePath: String,
        expectedUser: String,
        sessionAgentBundlePath: String,
        sessionAgentPort: Int,
        logFilePath: String
    ) {
        self.executablePath = executablePath
        self.launchDaemonLabel = launchDaemonLabel
        self.statusFilePath = statusFilePath
        self.expectedUser = expectedUser
        self.sessionAgentBundlePath = sessionAgentBundlePath
        self.sessionAgentPort = sessionAgentPort
        self.logFilePath = logFilePath
    }

    public static let guestDefault = BootstrapAgentConfiguration(
        executablePath: "/usr/local/libexec/computer-use/bootstrap-agent",
        launchDaemonLabel: "io.github.jianliang00.computer-use.bootstrap",
        statusFilePath: "/var/run/computer-use/bootstrap-status.json",
        expectedUser: "admin",
        sessionAgentBundlePath: "/Applications/ComputerUseAgent.app",
        sessionAgentPort: 7777,
        logFilePath: "/var/log/computer-use-bootstrap.log"
    )
}
