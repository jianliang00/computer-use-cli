public struct SessionAgentConfiguration: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var bundlePath: String
    public var launchAgentLabel: String
    public var host: String
    public var port: Int
    public var logFilePath: String

    public init(
        bundleIdentifier: String,
        bundlePath: String,
        launchAgentLabel: String,
        host: String,
        port: Int,
        logFilePath: String
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.launchAgentLabel = launchAgentLabel
        self.host = host
        self.port = port
        self.logFilePath = logFilePath
    }

    public static let guestDefault = SessionAgentConfiguration(
        bundleIdentifier: "com.jianliang00.computer-use-cli",
        bundlePath: "/Applications/ComputerUseAgent.app",
        launchAgentLabel: "io.github.jianliang00.computer-use.agent",
        host: "127.0.0.1",
        port: 7777,
        logFilePath: "/Users/admin/Library/Logs/ComputerUseAgent.log"
    )
}

public protocol SessionAgentConfiguring: Sendable {
    var configuration: SessionAgentConfiguration { get }
}
