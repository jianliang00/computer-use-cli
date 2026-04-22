import Foundation

public struct MachineMetadata: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case created
        case running
        case stopped
        case deleted
    }

    public let name: String
    public let imageReference: String
    public let sandboxID: String?
    public let hostPort: Int
    public let status: Status
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        name: String,
        imageReference: String,
        sandboxID: String?,
        hostPort: Int,
        status: Status,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.name = name
        self.imageReference = imageReference
        self.sandboxID = sandboxID
        self.hostPort = hostPort
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MachineMetadataStore {
    public static let defaultPortRange = 46_000...46_999

    private let fileManager: FileManager
    private let machinesDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil
    ) {
        self.fileManager = fileManager

        let baseDirectory = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        self.machinesDirectory = baseDirectory
            .appending(path: ".computer-use-cli", directoryHint: .isDirectory)
            .appending(path: "machines", directoryHint: .isDirectory)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
        ]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func create(_ metadata: MachineMetadata) throws {
        try ensureBaseDirectory()

        let machineDirectory = directory(for: metadata.name)
        guard fileManager.fileExists(atPath: machineDirectory.path) == false else {
            throw MachineStoreError.machineAlreadyExists(metadata.name)
        }

        try fileManager.createDirectory(
            at: machineDirectory,
            withIntermediateDirectories: true
        )
        try write(metadata, to: machineFileURL(for: metadata.name))
    }

    public func metadata(named name: String) throws -> MachineMetadata {
        let fileURL = machineFileURL(for: name)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw MachineStoreError.machineNotFound(name)
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(MachineMetadata.self, from: data)
    }

    public func allMetadata() throws -> [MachineMetadata] {
        try ensureBaseDirectory()

        let machineDirectories = try fileManager.contentsOfDirectory(
            at: machinesDirectory,
            includingPropertiesForKeys: nil
        )

        return try machineDirectories
            .filter { $0.hasDirectoryPath }
            .map { try metadata(named: $0.lastPathComponent) }
            .sorted { $0.name < $1.name }
    }

    public func update(_ metadata: MachineMetadata) throws {
        try ensureBaseDirectory()

        let fileURL = machineFileURL(for: metadata.name)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw MachineStoreError.machineNotFound(metadata.name)
        }

        try write(metadata, to: fileURL)
    }

    public func deleteMetadata(named name: String) throws {
        let machineDirectory = directory(for: name)
        guard fileManager.fileExists(atPath: machineDirectory.path) else {
            throw MachineStoreError.machineNotFound(name)
        }

        try fileManager.removeItem(at: machineDirectory)
    }

    public func allocateHostPort(requestedPort: Int? = nil) throws -> Int {
        let usedPorts = Set(try allMetadata().map(\.hostPort))

        if let requestedPort {
            guard Self.defaultPortRange.contains(requestedPort) else {
                throw MachineStoreError.portOutOfRange(requestedPort)
            }

            guard usedPorts.contains(requestedPort) == false else {
                throw MachineStoreError.portAlreadyAllocated(requestedPort)
            }

            return requestedPort
        }

        guard let port = Self.defaultPortRange.first(where: { usedPorts.contains($0) == false }) else {
            throw MachineStoreError.noAvailablePorts
        }

        return port
    }

    private func ensureBaseDirectory() throws {
        if fileManager.fileExists(atPath: machinesDirectory.path) == false {
            try fileManager.createDirectory(
                at: machinesDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    private func directory(for name: String) -> URL {
        machinesDirectory.appending(path: name, directoryHint: .isDirectory)
    }

    private func machineFileURL(for name: String) -> URL {
        directory(for: name).appending(path: "machine.json", directoryHint: .notDirectory)
    }

    private func write(_ metadata: MachineMetadata, to fileURL: URL) throws {
        let data = try encoder.encode(metadata)
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum MachineStoreError: Error, LocalizedError, Equatable {
    case machineAlreadyExists(String)
    case machineNotFound(String)
    case portAlreadyAllocated(Int)
    case portOutOfRange(Int)
    case noAvailablePorts

    public var errorDescription: String? {
        switch self {
        case let .machineAlreadyExists(name):
            "machine \(name) already exists"
        case let .machineNotFound(name):
            "machine \(name) was not found"
        case let .portAlreadyAllocated(port):
            "host port \(port) is already allocated"
        case let .portOutOfRange(port):
            "host port \(port) must be in 46000...46999"
        case .noAvailablePorts:
            "no available host ports remain in the default allocation range"
        }
    }
}
