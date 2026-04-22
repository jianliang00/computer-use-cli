import ComputerUseCLI
import Foundation
import Testing

@Test
func machineCreateAndInspectRoundTrip() throws {
    let homeDirectory = try temporaryDirectory()
    let tool = CommandLineTool(
        fileManager: .default,
        homeDirectory: homeDirectory,
        now: { Date(timeIntervalSince1970: 1_710_000_000) }
    )

    let created = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "demo",
        "--image", "local/computer-use:authorized",
    ])
    #expect(created.contains("\"name\" : \"demo\""))
    #expect(created.contains("\"hostPort\" : 46000"))

    let inspected = try tool.run(arguments: [
        "machine",
        "inspect",
        "--machine", "demo",
    ])
    #expect(inspected.contains("\"imageReference\" : \"local/computer-use:authorized\""))
}

@Test
func machineListReturnsStoredMachines() throws {
    let homeDirectory = try temporaryDirectory()
    let tool = CommandLineTool(
        fileManager: .default,
        homeDirectory: homeDirectory,
        now: { Date(timeIntervalSince1970: 1_710_000_100) }
    )

    _ = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "alpha",
        "--image", "local/computer-use:authorized",
    ])
    _ = try tool.run(arguments: [
        "machine",
        "create",
        "--name", "beta",
        "--image", "local/computer-use:product",
    ])

    let listOutput = try tool.run(arguments: ["machine", "list"])
    #expect(listOutput.contains("\"name\" : \"alpha\""))
    #expect(listOutput.contains("\"name\" : \"beta\""))
}

private func temporaryDirectory() throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}
