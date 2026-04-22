public struct BootstrapAgentConfiguration: Codable, Equatable, Sendable {
    public var executablePath: String
    public var launchDaemonLabel: String
    public var statusFilePath: String

    public init(
        executablePath: String,
        launchDaemonLabel: String,
        statusFilePath: String
    ) {
        self.executablePath = executablePath
        self.launchDaemonLabel = launchDaemonLabel
        self.statusFilePath = statusFilePath
    }

    public static let guestDefault = BootstrapAgentConfiguration(
        executablePath: "/usr/local/libexec/computer-use/bootstrap-agent",
        launchDaemonLabel: "io.github.jianliang00.computer-use.bootstrap",
        statusFilePath: "/var/run/computer-use/bootstrap-status.json"
    )
}
