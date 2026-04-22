import ContainerBridge
import Foundation

public struct CommandLineTool {
    private let machineService: MachineService

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let store = MachineMetadataStore(
            fileManager: fileManager,
            homeDirectory: homeDirectory
        )
        self.machineService = MachineService(store: store, now: now)
    }

    public func run(arguments: [String]) throws -> String {
        guard let command = arguments.first else {
            return usage()
        }

        switch command {
        case "machine":
            return try handleMachine(arguments: Array(arguments.dropFirst()))
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
        case "inspect":
            let name = try flags.requiredValue(for: "--machine")
            let metadata = try machineService.inspect(name: name)
            return try JSONOutput.render(metadata)
        case "list":
            return try JSONOutput.render(machineService.list())
        case "rm":
            let name = try flags.requiredValue(for: "--machine")
            try machineService.remove(name: name)
            return "removed \(name)"
        case "start", "stop", "logs":
            throw CLIError.notImplemented("machine \(subcommand)")
        default:
            throw CLIError.unknownSubcommand("machine", subcommand)
        }
    }

    private func usage() -> String {
        """
        Usage:
          computer-use machine create --name <name> --image <image> [--host-port <port>]
          computer-use machine inspect --machine <name>
          computer-use machine list
          computer-use machine rm --machine <name>
        """
    }
}

struct FlagParser {
    private let arguments: [String]

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func parse() throws -> ParsedFlags {
        var values: [String: String] = [:]
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
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

        return ParsedFlags(values: values)
    }
}

struct ParsedFlags {
    private let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }

    func requiredValue(for key: String) throws -> String {
        guard let value = values[key], value.isEmpty == false else {
            throw CLIError.missingValue(key)
        }

        return value
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
}

public enum CLIError: Error, LocalizedError, Equatable {
    case missingSubcommand(String)
    case unknownCommand(String)
    case unknownSubcommand(String, String)
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidIntegerFlag(String, String)
    case notImplemented(String)

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
        case let .notImplemented(feature):
            "\(feature) is not implemented yet"
        }
    }
}
