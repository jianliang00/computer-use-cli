import ContainerBridge
import Foundation

public struct MachineService {
    private let store: MachineMetadataStore
    private let containerBridge: any ContainerRuntimeBridging
    private let now: @Sendable () -> Date

    init(
        store: MachineMetadataStore,
        containerBridge: any ContainerRuntimeBridging,
        now: @escaping @Sendable () -> Date
    ) {
        self.store = store
        self.containerBridge = containerBridge
        self.now = now
    }

    public func create(
        name: String,
        imageReference: String,
        requestedHostPort: Int? = nil
    ) throws -> MachineMetadata {
        let timestamp = now()
        let port = try store.allocateHostPort(requestedPort: requestedHostPort)
        let metadata = MachineMetadata(
            name: name,
            imageReference: imageReference,
            sandboxID: nil,
            hostPort: port,
            status: .created,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try store.create(metadata)
        return metadata
    }

    public func inspect(name: String) throws -> MachineMetadata {
        let metadata = try store.metadata(named: name)

        guard let sandboxID = metadata.sandboxID else {
            return metadata
        }

        let details = try containerBridge.inspectSandbox(id: sandboxID)
        let updated = metadata.updating(from: details, updatedAt: now())
        try store.update(updated)
        return updated
    }

    public func list() -> [MachineMetadata] {
        (try? store.allMetadata()) ?? []
    }

    public func start(name: String) throws -> MachineMetadata {
        let metadata = try store.metadata(named: name)

        let details: SandboxDetails
        if let sandboxID = metadata.sandboxID {
            let current = try containerBridge.inspectSandbox(id: sandboxID)
            if current.status == .running {
                let updated = metadata.updating(from: current, updatedAt: now())
                try store.update(updated)
                return updated
            }

            details = try containerBridge.startSandbox(id: sandboxID)
        } else {
            let created = try containerBridge.createSandbox(
                configuration: SandboxConfiguration(
                    name: metadata.name,
                    imageReference: metadata.imageReference,
                    publishedHostPort: metadata.hostPort
                )
            )

            if created.status == .running {
                details = created
            } else {
                details = try containerBridge.startSandbox(id: created.sandboxID)
            }
        }

        let updated = metadata.updating(from: details, updatedAt: now())
        try store.update(updated)
        return updated
    }

    public func stop(name: String) throws -> MachineMetadata {
        let metadata = try store.metadata(named: name)
        guard let sandboxID = metadata.sandboxID else {
            throw MachineServiceError.sandboxNotCreated(name)
        }

        let current = try containerBridge.inspectSandbox(id: sandboxID)
        if current.status == .stopped {
            let updated = metadata.updating(from: current, updatedAt: now())
            try store.update(updated)
            return updated
        }

        let details = try containerBridge.stopSandbox(id: sandboxID)
        let updated = metadata.updating(from: details, updatedAt: now())
        try store.update(updated)
        return updated
    }

    public func logs(name: String) throws -> SandboxLogs {
        let metadata = try store.metadata(named: name)
        guard let sandboxID = metadata.sandboxID else {
            throw MachineServiceError.sandboxNotCreated(name)
        }

        return try containerBridge.queryLogs(id: sandboxID)
    }

    public func remove(name: String) throws {
        let metadata = try store.metadata(named: name)

        if let sandboxID = metadata.sandboxID {
            do {
                try containerBridge.removeSandbox(id: sandboxID)
            } catch let error as ContainerBridgeError {
                if error != .sandboxNotFound(sandboxID) {
                    throw error
                }
            }
        }

        try store.deleteMetadata(named: name)
    }
}

public enum MachineServiceError: Error, LocalizedError, Equatable {
    case sandboxNotCreated(String)

    public var errorDescription: String? {
        switch self {
        case let .sandboxNotCreated(name):
            "machine \(name) does not have a created sandbox yet"
        }
    }
}
