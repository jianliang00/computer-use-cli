import Foundation

public struct SandboxConfiguration: Equatable, Sendable {
    public let name: String
    public let imageReference: String
    public let publishedHostPort: Int

    public init(
        name: String,
        imageReference: String,
        publishedHostPort: Int
    ) {
        self.name = name
        self.imageReference = imageReference
        self.publishedHostPort = publishedHostPort
    }
}

public struct SandboxDetails: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case created
        case running
        case stopped
    }

    public let sandboxID: String
    public let name: String
    public let imageReference: String
    public let publishedHostPort: Int
    public let status: Status

    public init(
        sandboxID: String,
        name: String,
        imageReference: String,
        publishedHostPort: Int,
        status: Status
    ) {
        self.sandboxID = sandboxID
        self.name = name
        self.imageReference = imageReference
        self.publishedHostPort = publishedHostPort
        self.status = status
    }
}

public struct SandboxLogs: Equatable, Sendable {
    public let sandboxID: String
    public let entries: [String]

    public init(
        sandboxID: String,
        entries: [String]
    ) {
        self.sandboxID = sandboxID
        self.entries = entries
    }
}

public protocol ContainerRuntimeBridging: Sendable {
    func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails
    func startSandbox(id: String) throws -> SandboxDetails
    func inspectSandbox(id: String) throws -> SandboxDetails
    func stopSandbox(id: String) throws -> SandboxDetails
    func removeSandbox(id: String) throws
    func queryLogs(id: String) throws -> SandboxLogs
    func resolvePublishedHostPort(id: String) throws -> Int
}

public struct UnavailableContainerBridge: ContainerRuntimeBridging {
    public init() {}

    public func createSandbox(configuration: SandboxConfiguration) throws -> SandboxDetails {
        throw ContainerBridgeError.notImplemented("createSandbox")
    }

    public func startSandbox(id: String) throws -> SandboxDetails {
        throw ContainerBridgeError.notImplemented("startSandbox")
    }

    public func inspectSandbox(id: String) throws -> SandboxDetails {
        throw ContainerBridgeError.notImplemented("inspectSandbox")
    }

    public func stopSandbox(id: String) throws -> SandboxDetails {
        throw ContainerBridgeError.notImplemented("stopSandbox")
    }

    public func removeSandbox(id: String) throws {
        throw ContainerBridgeError.notImplemented("removeSandbox")
    }

    public func queryLogs(id: String) throws -> SandboxLogs {
        throw ContainerBridgeError.notImplemented("queryLogs")
    }

    public func resolvePublishedHostPort(id: String) throws -> Int {
        throw ContainerBridgeError.notImplemented("resolvePublishedHostPort")
    }
}

public enum ContainerBridgeError: Error, LocalizedError, Equatable {
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case let .notImplemented(method):
            "\(method) is not implemented yet"
        }
    }
}
