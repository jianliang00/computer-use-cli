import AgentProtocol
import ContainerBridge
import Foundation

public struct CommandLineTool {
    private let machineService: MachineService
    private let agentClient: any AgentClienting

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        containerBridge: any ContainerRuntimeBridging = ContainerCLIBridge(),
        agentClient: any AgentClienting = AgentHTTPClient()
    ) {
        let store = MachineMetadataStore(
            fileManager: fileManager,
            homeDirectory: homeDirectory
        )
        self.machineService = MachineService(
            store: store,
            containerBridge: containerBridge,
            now: now
        )
        self.agentClient = agentClient
    }

    public func run(arguments: [String]) throws -> String {
        guard let command = arguments.first else {
            return usage()
        }

        switch command {
        case "machine":
            return try handleMachine(arguments: Array(arguments.dropFirst()))
        case "agent":
            return try handleAgent(arguments: Array(arguments.dropFirst()))
        case "permissions":
            return try handlePermissions(arguments: Array(arguments.dropFirst()))
        case "apps":
            return try handleApps(arguments: Array(arguments.dropFirst()))
        case "state":
            return try handleState(arguments: Array(arguments.dropFirst()))
        case "action", "actions":
            return try handleAction(arguments: Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            return usage()
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private func handleMachine(arguments: [String]) throws -> String {
        guard let subcommand = arguments.first else {
            throw CLIError.missingSubcommand("machine")
        }

        let flags = try FlagParser(arguments: Array(arguments.dropFirst())).parse()

        switch subcommand {
        case "create":
            let name = try flags.requiredValue(for: "--name")
            let image = try flags.requiredValue(for: "--image")
            let requestedPort = try flags.optionalIntValue(for: "--host-port")
            let metadata = try machineService.create(
                name: name,
                imageReference: image,
                requestedHostPort: requestedPort
            )
            return try JSONOutput.render(metadata)
        case "start":
            let name = try flags.requiredValue(for: "--machine")
            let metadata = try machineService.start(
                name: name,
                initProcessArguments: flags.passthroughArguments
            )
            return try JSONOutput.render(metadata)
        case "inspect":
            let name = try flags.requiredValue(for: "--machine")
            let metadata = try machineService.inspect(name: name)
            return try JSONOutput.render(metadata)
        case "stop":
            let name = try flags.requiredValue(for: "--machine")
            let metadata = try machineService.stop(name: name)
            return try JSONOutput.render(metadata)
        case "logs":
            let name = try flags.requiredValue(for: "--machine")
            let logs = try machineService.logs(name: name)
            return logs.entries.joined(separator: "\n")
        case "list":
            return try JSONOutput.render(machineService.list())
        case "rm":
            let name = try flags.requiredValue(for: "--machine")
            try machineService.remove(name: name)
            return "removed \(name)"
        default:
            throw CLIError.unknownSubcommand("machine", subcommand)
        }
    }

    private func handleAgent(arguments: [String]) throws -> String {
        guard let subcommand = arguments.first else {
            throw CLIError.missingSubcommand("agent")
        }

        let flags = try FlagParser(arguments: Array(arguments.dropFirst())).parse()

        switch subcommand {
        case "ping":
            let name = try flags.requiredValue(for: "--machine")
            let baseURL = try agentBaseURL(forMachine: name)
            return try JSONOutput.render(agentClient.health(baseURL: baseURL))
        case "doctor":
            let name = try flags.requiredValue(for: "--machine")
            return try JSONOutput.render(agentDoctorReport(machineName: name))
        default:
            throw CLIError.unknownSubcommand("agent", subcommand)
        }
    }

    private func handlePermissions(arguments: [String]) throws -> String {
        guard let subcommand = arguments.first else {
            throw CLIError.missingSubcommand("permissions")
        }

        let flags = try FlagParser(arguments: Array(arguments.dropFirst())).parse()

        switch subcommand {
        case "get":
            let name = try flags.requiredValue(for: "--machine")
            let baseURL = try agentBaseURL(forMachine: name)
            return try JSONOutput.render(agentClient.permissions(baseURL: baseURL))
        default:
            throw CLIError.unknownSubcommand("permissions", subcommand)
        }
    }

    private func handleApps(arguments: [String]) throws -> String {
        guard let subcommand = arguments.first else {
            throw CLIError.missingSubcommand("apps")
        }

        let flags = try FlagParser(arguments: Array(arguments.dropFirst())).parse()

        switch subcommand {
        case "list":
            let name = try flags.requiredValue(for: "--machine")
            let baseURL = try agentBaseURL(forMachine: name)
            return try JSONOutput.render(agentClient.apps(baseURL: baseURL))
        default:
            throw CLIError.unknownSubcommand("apps", subcommand)
        }
    }

    private func handleState(arguments: [String]) throws -> String {
        guard let subcommand = arguments.first else {
            throw CLIError.missingSubcommand("state")
        }

        let flags = try FlagParser(arguments: Array(arguments.dropFirst())).parse()

        switch subcommand {
        case "get":
            let name = try flags.requiredValue(for: "--machine")
            let baseURL = try agentBaseURL(forMachine: name)
            let request = StateRequest(bundleID: flags.optionalValue(for: "--bundle-id"))
            return try JSONOutput.render(agentClient.state(baseURL: baseURL, request: request))
        default:
            throw CLIError.unknownSubcommand("state", subcommand)
        }
    }

    private func handleAction(arguments: [String]) throws -> String {
        guard let subcommand = arguments.first else {
            throw CLIError.missingSubcommand("action")
        }

        let flags = try FlagParser(arguments: Array(arguments.dropFirst())).parse()
        let name = try flags.requiredValue(for: "--machine")
        let baseURL = try agentBaseURL(forMachine: name)

        switch subcommand {
        case "click":
            return try JSONOutput.render(agentClient.click(
                baseURL: baseURL,
                request: ClickActionRequest(
                    target: try clickTarget(from: flags),
                    button: try mouseButton(from: flags.optionalValue(for: "--button")),
                    clickCount: try flags.optionalIntValue(for: "--click-count") ?? 1
                )
            ))
        case "type":
            return try JSONOutput.render(agentClient.type(
                baseURL: baseURL,
                request: TypeActionRequest(text: try textValue(from: flags))
            ))
        case "key":
            return try JSONOutput.render(agentClient.key(
                baseURL: baseURL,
                request: KeyActionRequest(key: try flags.requiredValue(for: "--key"))
            ))
        case "drag":
            return try JSONOutput.render(agentClient.drag(
                baseURL: baseURL,
                request: DragActionRequest(
                    from: Point(
                        x: try flags.requiredDoubleValue(for: "--from-x"),
                        y: try flags.requiredDoubleValue(for: "--from-y")
                    ),
                    to: Point(
                        x: try flags.requiredDoubleValue(for: "--to-x"),
                        y: try flags.requiredDoubleValue(for: "--to-y")
                    )
                )
            ))
        case "scroll":
            return try JSONOutput.render(agentClient.scroll(
                baseURL: baseURL,
                request: ScrollActionRequest(
                    target: try elementReference(from: flags),
                    direction: try scrollDirection(from: flags.requiredValue(for: "--direction")),
                    pages: try flags.optionalIntValue(for: "--pages") ?? 1
                )
            ))
        case "set-value":
            return try JSONOutput.render(agentClient.setValue(
                baseURL: baseURL,
                request: SetValueActionRequest(
                    target: try elementReference(from: flags),
                    value: try flags.requiredValue(for: "--value")
                )
            ))
        case "action":
            return try JSONOutput.render(agentClient.perform(
                baseURL: baseURL,
                request: ElementActionRequest(
                    target: try elementReference(from: flags),
                    name: try flags.requiredValue(for: "--name")
                )
            ))
        default:
            throw CLIError.unknownSubcommand("action", subcommand)
        }
    }

    private func agentDoctorReport(machineName: String) throws -> AgentDoctorReport {
        let metadata = try machineService.inspect(name: machineName)
        let baseURL = try agentBaseURL(from: metadata)
        var health: HealthResponse?
        var permissions: PermissionsResponse?
        var errors: [String] = []

        if metadata.status == .running {
            do {
                health = try agentClient.health(baseURL: baseURL)
            } catch {
                errors.append(error.localizedDescription)
            }

            do {
                permissions = try agentClient.permissions(baseURL: baseURL)
            } catch {
                errors.append(error.localizedDescription)
            }
        } else {
            errors.append("machine \(machineName) is \(metadata.status.rawValue), not running")
        }

        return AgentDoctorReport(
            machine: machineName,
            sandboxID: metadata.sandboxID,
            sandboxRunning: metadata.status == .running,
            publishedHostPort: metadata.hostPort,
            agentTransport: metadata.agentTransport,
            bootstrapReady: nil,
            sessionAgentReady: health?.ok == true,
            accessibility: permissions?.accessibility,
            screenRecording: permissions?.screenRecording,
            errors: errors
        )
    }

    private func agentBaseURL(forMachine name: String) throws -> URL {
        let metadata = try machineService.inspect(name: name)
        guard metadata.status == .running else {
            throw CLIError.machineNotRunning(name, metadata.status.rawValue)
        }

        return try agentBaseURL(from: metadata)
    }

    private func agentBaseURL(from metadata: MachineMetadata) throws -> URL {
        switch metadata.agentTransport {
        case .publishedTCP:
            return URL(string: "http://127.0.0.1:\(metadata.hostPort)")!
        case .containerExec:
            guard let sandboxID = metadata.sandboxID else {
                throw CLIError.sandboxNotCreated(metadata.name)
            }

            return URL(string: "container-exec://\(sandboxID)")!
        }
    }

    private func clickTarget(from flags: ParsedFlags) throws -> ClickActionRequest.Target {
        let hasCoordinates = flags.hasValue(for: "--x") || flags.hasValue(for: "--y")
        let hasElement = flags.hasValue(for: "--snapshot-id") || flags.hasValue(for: "--element-id")

        switch (hasCoordinates, hasElement) {
        case (true, false):
            return .coordinates(Point(
                x: try flags.requiredDoubleValue(for: "--x"),
                y: try flags.requiredDoubleValue(for: "--y")
            ))
        case (false, true):
            return .element(try elementReference(from: flags))
        default:
            throw CLIError.invalidFlagCombination(
                "click requires either --x/--y or --snapshot-id/--element-id"
            )
        }
    }

    private func elementReference(from flags: ParsedFlags) throws -> SnapshotElementReference {
        SnapshotElementReference(
            snapshotID: try flags.requiredValue(for: "--snapshot-id"),
            elementID: try flags.requiredValue(for: "--element-id")
        )
    }

    private func textValue(from flags: ParsedFlags) throws -> String {
        if let text = flags.optionalValue(for: "--text"), text.isEmpty == false {
            return text
        }

        let passthroughText = flags.passthroughArguments.joined(separator: " ")
        guard passthroughText.isEmpty == false else {
            throw CLIError.missingValue("--text")
        }

        return passthroughText
    }

    private func mouseButton(from rawValue: String?) throws -> MouseButton {
        let value = rawValue ?? MouseButton.left.rawValue
        guard let button = MouseButton(rawValue: value) else {
            throw CLIError.invalidFlagValue("--button", value)
        }

        return button
    }

    private func scrollDirection(from rawValue: String) throws -> ScrollDirection {
        guard let direction = ScrollDirection(rawValue: rawValue) else {
            throw CLIError.invalidFlagValue("--direction", rawValue)
        }

        return direction
    }

    private func usage() -> String {
        """
        Usage:
          computer-use machine create --name <name> --image <image> [--host-port <port>]
          computer-use machine start --machine <name> [-- <command> [args...]]
          computer-use machine inspect --machine <name>
          computer-use machine stop --machine <name>
          computer-use machine list
          computer-use machine logs --machine <name>
          computer-use machine rm --machine <name>
          computer-use agent ping --machine <name>
          computer-use agent doctor --machine <name>
          computer-use permissions get --machine <name>
          computer-use apps list --machine <name>
          computer-use state get --machine <name> [--bundle-id <bundle-id>]
          computer-use action click --machine <name> (--x <x> --y <y> | --snapshot-id <id> --element-id <id>)
          computer-use action type --machine <name> --text <text>
          computer-use action key --machine <name> --key <key>
          computer-use action drag --machine <name> --from-x <x> --from-y <y> --to-x <x> --to-y <y>
          computer-use action scroll --machine <name> --snapshot-id <id> --element-id <id> --direction <up|down|left|right> [--pages <n>]
          computer-use action set-value --machine <name> --snapshot-id <id> --element-id <id> --value <value>
          computer-use action action --machine <name> --snapshot-id <id> --element-id <id> --name <AXAction>
        """
    }
}

public struct AgentDoctorReport: Encodable, Equatable, Sendable {
    public let machine: String
    public let sandboxID: String?
    public let sandboxRunning: Bool
    public let publishedHostPort: Int
    public let agentTransport: MachineAgentTransport
    public let bootstrapReady: Bool?
    public let sessionAgentReady: Bool
    public let accessibility: Bool?
    public let screenRecording: Bool?
    public let errors: [String]

    public init(
        machine: String,
        sandboxID: String?,
        sandboxRunning: Bool,
        publishedHostPort: Int,
        agentTransport: MachineAgentTransport = .publishedTCP,
        bootstrapReady: Bool?,
        sessionAgentReady: Bool,
        accessibility: Bool?,
        screenRecording: Bool?,
        errors: [String]
    ) {
        self.machine = machine
        self.sandboxID = sandboxID
        self.sandboxRunning = sandboxRunning
        self.publishedHostPort = publishedHostPort
        self.agentTransport = agentTransport
        self.bootstrapReady = bootstrapReady
        self.sessionAgentReady = sessionAgentReady
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.errors = errors
    }

    private enum CodingKeys: String, CodingKey {
        case machine
        case sandboxID = "sandbox_id"
        case sandboxRunning = "sandbox_running"
        case publishedHostPort = "published_host_port"
        case agentTransport = "agent_transport"
        case bootstrapReady = "bootstrap_ready"
        case sessionAgentReady = "session_agent_ready"
        case accessibility
        case screenRecording = "screen_recording"
        case errors
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(machine, forKey: .machine)
        try container.encode(sandboxID, forKey: .sandboxID)
        try container.encode(sandboxRunning, forKey: .sandboxRunning)
        try container.encode(publishedHostPort, forKey: .publishedHostPort)
        try container.encode(agentTransport, forKey: .agentTransport)
        try container.encode(bootstrapReady, forKey: .bootstrapReady)
        try container.encode(sessionAgentReady, forKey: .sessionAgentReady)
        try container.encode(accessibility, forKey: .accessibility)
        try container.encode(screenRecording, forKey: .screenRecording)
        try container.encode(errors, forKey: .errors)
    }
}

struct FlagParser {
    private let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func parse() throws -> ParsedFlags {
        var values: [String: String] = [:]
        var passthroughArguments: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                passthroughArguments = Array(arguments.dropFirst(index + 1))
                break
            }

            guard argument.hasPrefix("--") else {
                throw CLIError.unexpectedArgument(argument)
            }

            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw CLIError.missingValue(argument)
            }

            values[argument] = arguments[valueIndex]
            index += 2
        }

        return ParsedFlags(values: values, passthroughArguments: passthroughArguments)
    }
}

struct ParsedFlags {
    private let values: [String: String]
    let passthroughArguments: [String]

    init(
        values: [String: String],
        passthroughArguments: [String]
    ) {
        self.values = values
        self.passthroughArguments = passthroughArguments
    }

    func requiredValue(for key: String) throws -> String {
        guard let value = values[key], value.isEmpty == false else {
            throw CLIError.missingValue(key)
        }

        return value
    }

    func optionalValue(for key: String) -> String? {
        values[key]
    }

    func hasValue(for key: String) -> Bool {
        values[key] != nil
    }

    func optionalIntValue(for key: String) throws -> Int? {
        guard let rawValue = values[key] else {
            return nil
        }

        guard let value = Int(rawValue) else {
            throw CLIError.invalidIntegerFlag(key, rawValue)
        }

        return value
    }

    func requiredDoubleValue(for key: String) throws -> Double {
        let rawValue = try requiredValue(for: key)
        guard let value = Double(rawValue) else {
            throw CLIError.invalidDoubleFlag(key, rawValue)
        }

        return value
    }
}

public enum CLIError: Error, LocalizedError, Equatable {
    case missingSubcommand(String)
    case unknownCommand(String)
    case unknownSubcommand(String, String)
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidIntegerFlag(String, String)
    case invalidDoubleFlag(String, String)
    case invalidFlagValue(String, String)
    case invalidFlagCombination(String)
    case machineNotRunning(String, String)
    case sandboxNotCreated(String)

    public var errorDescription: String? {
        switch self {
        case let .missingSubcommand(command):
            "missing subcommand for \(command)"
        case let .unknownCommand(command):
            "unknown command \(command)"
        case let .unknownSubcommand(command, subcommand):
            "unknown subcommand \(subcommand) for \(command)"
        case let .unexpectedArgument(argument):
            "unexpected argument \(argument)"
        case let .missingValue(flag):
            "missing value for \(flag)"
        case let .invalidIntegerFlag(flag, value):
            "invalid integer value \(value) for \(flag)"
        case let .invalidDoubleFlag(flag, value):
            "invalid number value \(value) for \(flag)"
        case let .invalidFlagValue(flag, value):
            "invalid value \(value) for \(flag)"
        case let .invalidFlagCombination(message):
            message
        case let .machineNotRunning(name, status):
            "machine \(name) is \(status), not running"
        case let .sandboxNotCreated(name):
            "machine \(name) does not have a created sandbox"
        }
    }
}
