import ComputerUseCLI
import Foundation
import Testing

@Test
func machineMetadataStoreCreatesReadsUpdatesAndDeletes() throws {
    let homeDirectory = try temporaryDirectory()
    let store = MachineMetadataStore(homeDirectory: homeDirectory)
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)

    let metadata = MachineMetadata(
        name: "demo",
        imageReference: "local/computer-use:authorized",
        sandboxID: "sandbox-123",
        hostPort: 46042,
        status: .created,
        createdAt: createdAt,
        updatedAt: createdAt
    )

    try store.create(metadata)
    let loaded = try store.metadata(named: "demo")
    #expect(loaded == metadata)

    let updated = MachineMetadata(
        name: metadata.name,
        imageReference: metadata.imageReference,
        sandboxID: metadata.sandboxID,
        hostPort: metadata.hostPort,
        status: .running,
        createdAt: metadata.createdAt,
        updatedAt: Date(timeIntervalSince1970: 1_710_000_100)
    )
    try store.update(updated)
    #expect(try store.metadata(named: "demo") == updated)

    try store.deleteMetadata(named: "demo")

    do {
        _ = try store.metadata(named: "demo")
        Issue.record("expected machine lookup to fail after deletion")
    } catch let error as MachineStoreError {
        #expect(error == .machineNotFound("demo"))
    }
}

@Test
func machineMetadataStoreDetectsAllocatedPorts() throws {
    let homeDirectory = try temporaryDirectory()
    let store = MachineMetadataStore(homeDirectory: homeDirectory)
    let timestamp = Date(timeIntervalSince1970: 1_710_000_000)

    try store.create(
        MachineMetadata(
            name: "alpha",
            imageReference: "local/computer-use:authorized",
            sandboxID: nil,
            hostPort: 46000,
            status: .created,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    )

    #expect(try store.allocateHostPort() == 46001)

    do {
        _ = try store.allocateHostPort(requestedPort: 46000)
        Issue.record("expected duplicate port allocation to fail")
    } catch let error as MachineStoreError {
        #expect(error == .portAlreadyAllocated(46000))
    }
}

private func temporaryDirectory() throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}
