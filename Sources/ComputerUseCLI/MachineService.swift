import Foundation

public struct MachineService {
    private let store: MachineMetadataStore
    private let now: @Sendable () -> Date

    init(
        store: MachineMetadataStore,
        now: @escaping @Sendable () -> Date
    ) {
        self.store = store
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
        try store.metadata(named: name)
    }

    public func list() -> [MachineMetadata] {
        (try? store.allMetadata()) ?? []
    }

    public func remove(name: String) throws {
        try store.deleteMetadata(named: name)
    }
}
