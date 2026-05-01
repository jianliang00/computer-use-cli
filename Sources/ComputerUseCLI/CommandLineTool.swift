import AgentProtocol
import ContainerBridge
import CryptoKit
import Darwin
import Foundation

public struct CommandLineTool {
    private static let defaultFileChunkSize = 64 * 1024

    private let fileManager: FileManager
    private let machineService: MachineService
    private let agentClient: any AgentClienting
    private let containerRuntimeLayout: ContainerRuntimeLayout
    private let containerRuntimeBootstrapper: any ContainerRuntimeBootstrapping
    private let runtimeContainerRunner: any ContainerCommandRunning
    private let runtimeSystemController: (any ContainerRuntimeSystemControlling)?
    private let runtimeRestartConfirmation: @Sendable (ContainerBridgeError) -> Bool

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        containerBridge: (any ContainerRuntimeBridging)? = nil,
        agentClient: any AgentClienting = AgentHTTPClient(),
        containerRuntimeLayout: ContainerRuntimeLayout = .default(),
        containerRuntimeBootstrapper: any ContainerRuntimeBootstrapping = PublishedContainerRuntimeBootstrapper(),
        runtimeContainerRunner: (any ContainerCommandRunning)? = nil,
        runtimeSystemController: (any ContainerRuntimeSystemControlling)? = nil,
        runtimeRestartConfirmation: @escaping @Sendable (ContainerBridgeError) -> Bool = CommandLineTool.confirmRuntimeRestartInteractively
    ) {
        let runner = runtimeContainerRunner ?? ProcessContainerCommandRunner(
            layout: containerRuntimeLayout,
            bootstrapper: containerRuntimeBootstrapper
        )
        let bridge = containerBridge ?? ContainerCLIBridge(runner: runner)
        let store = MachineMetadataStore(
            fileManager: fileManager,
            homeDirectory: homeDirectory
        )
        self.fileManager = fileManager
        self.machineService = MachineService(
            store: store,
            containerBridge: bridge,
            now: now
        )
        self.agentClient = agentClient
        self.containerRuntimeLayout = containerRuntimeLayout
        self.containerRuntimeBootstrapper = containerRuntimeBootstrapper
        self.runtimeContainerRunner = runner
        self.runtimeSystemController = runtimeSystemController ?? (runner as? any ContainerRuntimeSystemControlling)
        self.runtimeRestartConfirmation = runtimeRestartConfirmation
    }

    public static func confirmRuntimeRestartInteractively(_ error: ContainerBridgeError) -> Bool {
        guard isatty(STDIN_FILENO) == 1 else {
            return false
        }

        writeStandardError(runtimeRestartPrompt(for: error))

        guard let response = readLine(strippingNewline: true) else {
            return false
        }

        let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "y" || normalized == "yes"
    }

    public func run(arguments: [String]) throws -> String {
        guard let command = arguments.first else {
            return usage()
        }

        switch command {
        case "machine":
            return try handleMachine(arguments: Array(arguments.dropFirst()))
        case "runtime":
            return try handleRuntime(arguments: Array(arguments.dropFirst()))
        case "agent":
            return try handleAgent(arguments: Array(arguments.dropFirst()))
        case "permissions":
            return try handlePermissions(arguments: Array(arguments.dropFirst()))
        case "apps":
            return try handleApps(arguments: Array(arguments.dropFirst()))
        case "state":
            return try handleState(arguments: Array(arguments.dropFirst()))
        case "file", "files":
            return try handleFiles(arguments: Array(arguments.dropFirst()))
        case "action", "actions":
            return try handleAction(arguments: Array(arguments.dropFirst()))
        case "help", "--help", "-h":
            return usage()
        default:
            throw CLIError.unknownCommand(command)
        }
    }

    private func handleRuntime(arguments: [String]) throws -> String {
        guard let subcommand = arguments.first else {
            throw CLIError.missingSubcommand("runtime")
        }

        switch subcommand {
        case "info":
            return try JSONOutput.render(ContainerRuntimeReport(
                layout: containerRuntimeLayout,
                bootstrapped: nil
            ))
        case "bootstrap":
            try containerRuntimeBootstrapper.prepareRuntime(layout: containerRuntimeLayout)
            return try JSONOutput.render(ContainerRuntimeReport(
                layout: containerRuntimeLayout,
                bootstrapped: true
            ))
        case "container":
            var containerArguments = Array(arguments.dropFirst())
            if containerArguments.first == "--" {
                containerArguments.removeFirst()
            }
            guard containerArguments.isEmpty == false else {
                throw CLIError.missingValue("container arguments")
            }

            let result = try runtimeContainerRunner.run(arguments: containerArguments)
            return [result.stdout, result.stderr]
                .filter { $0.isEmpty == false }
                .joined(separator: "\n")
        default:
            throw CLIError.unknownSubcommand("runtime", subcommand)
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
            let metadata = try startMachine(
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

    private func startMachine(
        name: String,
        initProcessArguments: [String]
    ) throws -> MachineMetadata {
        do {
            return try machineService.start(
                name: name,
                initProcessArguments: initProcessArguments
            )
        } catch let error as ContainerBridgeError where error.isRuntimeRootMismatch {
            guard let runtimeSystemController else {
                throw error
            }

            guard runtimeRestartConfirmation(error) else {
                throw error
            }

            try runtimeSystemController.restartSystem()
            return try machineService.start(
                name: name,
                initProcessArguments: initProcessArguments
            )
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
        case "request":
            let name = try flags.requiredValue(for: "--machine")
            let baseURL = try agentBaseURL(forMachine: name)
            return try JSONOutput.render(agentClient.requestPermissions(baseURL: baseURL))
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
            let request = StateRequest(
                bundleID: flags.optionalValue(for: "--bundle-id"),
                app: flags.optionalValue(for: "--app")
            )
            return try JSONOutput.render(agentClient.state(baseURL: baseURL, request: request))
        default:
            throw CLIError.unknownSubcommand("state", subcommand)
        }
    }

    private func handleFiles(arguments: [String]) throws -> String {
        guard let subcommand = arguments.first else {
            throw CLIError.missingSubcommand("files")
        }

        let flags = try FlagParser(arguments: Array(arguments.dropFirst())).parse()
        let name = try flags.requiredValue(for: "--machine")
        let chunkSize = try fileChunkSize(from: flags)
        let overwrite = try flags.optionalBoolValue(for: "--overwrite") ?? true
        let createDirectories = try flags.optionalBoolValue(for: "--create-directories") ?? true

        switch subcommand {
        case "push":
            return try JSONOutput.render(pushFile(
                machineName: name,
                sourcePath: try flags.requiredValue(for: "--src"),
                destinationPath: try flags.requiredValue(for: "--dest"),
                chunkSize: chunkSize,
                overwrite: overwrite,
                createDirectories: createDirectories
            ))
        case "pull":
            return try JSONOutput.render(pullFile(
                machineName: name,
                sourcePath: try flags.requiredValue(for: "--src"),
                destinationPath: try flags.requiredValue(for: "--dest"),
                chunkSize: chunkSize,
                overwrite: overwrite,
                createDirectories: createDirectories
            ))
        default:
            throw CLIError.unknownSubcommand("files", subcommand)
        }
    }

    private func pushFile(
        machineName: String,
        sourcePath: String,
        destinationPath: String,
        chunkSize: Int,
        overwrite: Bool,
        createDirectories: Bool
    ) throws -> FileTransferReport {
        let sourceURL = try hostURL(from: sourcePath)
        let sourceKind = try hostItemKind(sourceURL, flag: "--src")

        switch sourceKind {
        case .file:
            return try pushLocalPayload(
                machineName: machineName,
                payloadURL: sourceURL,
                reportSourceURL: sourceURL,
                destinationPath: destinationPath,
                kind: "file",
                archiveFormat: nil,
                chunkSize: chunkSize,
                overwrite: overwrite,
                createDirectories: createDirectories
            )
        case .directory:
            let archiveURL = try createHostDirectoryArchive(sourceURL)
            defer {
                try? fileManager.removeItem(at: archiveURL)
            }
            return try pushLocalPayload(
                machineName: machineName,
                payloadURL: archiveURL,
                reportSourceURL: sourceURL,
                destinationPath: destinationPath,
                kind: "directory",
                archiveFormat: .tarGzip,
                chunkSize: chunkSize,
                overwrite: overwrite,
                createDirectories: createDirectories
            )
        }
    }

    private func pushLocalPayload(
        machineName: String,
        payloadURL: URL,
        reportSourceURL: URL,
        destinationPath: String,
        kind: String,
        archiveFormat: FileArchiveFormat?,
        chunkSize: Int,
        overwrite: Bool,
        createDirectories: Bool
    ) throws -> FileTransferReport {
        try requireRegularHostPayload(payloadURL)

        let digest = try fileDigest(at: payloadURL)
        let baseURL = try agentBaseURL(forMachine: machineName)
        let upload = try agentClient.startFileUpload(
            baseURL: baseURL,
            request: FileUploadStartRequest(
                path: destinationPath,
                expectedBytes: digest.bytes,
                sha256: digest.sha256,
                overwrite: overwrite,
                createDirectories: createDirectories,
                archiveFormat: archiveFormat
            )
        )

        let handle = try FileHandle(forReadingFrom: payloadURL)
        defer {
            try? handle.close()
        }

        var offset: Int64 = 0
        var chunks = 0
        while let chunk = try handle.read(upToCount: chunkSize), chunk.isEmpty == false {
            let response = try agentClient.uploadFileChunk(
                baseURL: baseURL,
                request: FileUploadChunkRequest(
                    uploadID: upload.uploadID,
                    offset: offset,
                    base64: chunk.base64EncodedString(),
                    sha256: sha256Hex(chunk)
                )
            )
            let nextOffset = offset + Int64(chunk.count)
            guard response.offset == offset,
                  response.bytes == Int64(chunk.count),
                  response.receivedBytes == nextOffset
            else {
                throw CLIError.fileTransferFailed("agent returned inconsistent upload progress")
            }

            offset = nextOffset
            chunks += 1
        }

        guard offset == digest.bytes else {
            throw CLIError.fileTransferFailed("read \(offset) bytes, expected \(digest.bytes)")
        }

        let finished = try agentClient.finishFileUpload(
            baseURL: baseURL,
            request: FileUploadFinishRequest(uploadID: upload.uploadID)
        )
        try validateTransferDigest(finished, expected: digest)

        return FileTransferReport(
            direction: "push",
            kind: kind,
            machine: machineName,
            source: reportSourceURL.path,
            destination: finished.path,
            bytes: finished.bytes,
            sha256: finished.sha256,
            chunks: chunks
        )
    }

    private func pullFile(
        machineName: String,
        sourcePath: String,
        destinationPath: String,
        chunkSize: Int,
        overwrite: Bool,
        createDirectories: Bool
    ) throws -> FileTransferReport {
        let baseURL = try agentBaseURL(forMachine: machineName)
        let stat = try agentClient.statFile(
            baseURL: baseURL,
            request: FileStatRequest(path: sourcePath)
        )

        switch stat.kind {
        case .file:
            return try pullRegularFile(
                machineName: machineName,
                baseURL: baseURL,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                chunkSize: chunkSize,
                overwrite: overwrite,
                createDirectories: createDirectories
            )
        case .directory:
            return try pullDirectory(
                machineName: machineName,
                baseURL: baseURL,
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                chunkSize: chunkSize,
                overwrite: overwrite,
                createDirectories: createDirectories
            )
        }
    }

    private func pullRegularFile(
        machineName: String,
        baseURL: URL,
        sourcePath: String,
        destinationPath: String,
        chunkSize: Int,
        overwrite: Bool,
        createDirectories: Bool
    ) throws -> FileTransferReport {
        let destinationURL = try hostURL(from: destinationPath)
        try prepareHostDestination(
            destinationURL,
            overwrite: overwrite,
            createDirectories: createDirectories
        )

        let download = try agentClient.startFileDownload(
            baseURL: baseURL,
            request: FileDownloadStartRequest(path: sourcePath)
        )

        let parentURL = destinationURL.deletingLastPathComponent()
        let tempURL = parentURL.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).computer-use-\(UUID().uuidString)"
        )
        guard fileManager.createFile(atPath: tempURL.path, contents: nil) else {
            throw CLIError.fileTransferFailed("unable to create temporary destination \(tempURL.path)")
        }

        var offset: Int64 = 0
        var chunks = 0
        var hasher = SHA256()
        let handle = try FileHandle(forWritingTo: tempURL)

        do {
            while offset < download.bytes {
                let length = Int(min(Int64(chunkSize), download.bytes - offset))
                let response = try agentClient.downloadFileChunk(
                    baseURL: baseURL,
                    request: FileDownloadChunkRequest(
                        downloadID: download.downloadID,
                        offset: offset,
                        length: length
                    )
                )
                guard response.offset == offset else {
                    throw CLIError.fileTransferFailed("agent returned chunk offset \(response.offset), expected \(offset)")
                }
                guard let chunk = Data(base64Encoded: response.base64) else {
                    throw CLIError.fileTransferFailed("agent returned invalid chunk base64")
                }
                guard Int64(chunk.count) == response.bytes else {
                    throw CLIError.fileTransferFailed("agent returned inconsistent chunk byte count")
                }
                guard sha256Hex(chunk) == response.sha256 else {
                    throw CLIError.fileTransferFailed("agent returned chunk with invalid sha256")
                }

                try handle.write(contentsOf: chunk)
                hasher.update(data: chunk)
                offset += Int64(chunk.count)
                chunks += 1

                if response.eof && offset < download.bytes {
                    throw CLIError.fileTransferFailed("agent ended download before the expected byte count")
                }
            }

            try handle.close()

            let actualDigest = LocalFileDigest(bytes: offset, sha256: hex(hasher.finalize()))
            let expectedDigest = LocalFileDigest(bytes: download.bytes, sha256: download.sha256)
            try validateTransferDigest(
                FileTransferResponse(path: download.path, bytes: actualDigest.bytes, sha256: actualDigest.sha256),
                expected: expectedDigest
            )

            _ = try agentClient.finishFileDownload(
                baseURL: baseURL,
                request: FileDownloadFinishRequest(downloadID: download.downloadID)
            )

            try moveDownloadedFile(from: tempURL, to: destinationURL)
        } catch {
            try? handle.close()
            try? fileManager.removeItem(at: tempURL)
            throw error
        }

        return FileTransferReport(
            direction: "pull",
            kind: "file",
            machine: machineName,
            source: download.path,
            destination: destinationURL.path,
            bytes: download.bytes,
            sha256: download.sha256,
            chunks: chunks
        )
    }

    private func pullDirectory(
        machineName: String,
        baseURL: URL,
        sourcePath: String,
        destinationPath: String,
        chunkSize: Int,
        overwrite: Bool,
        createDirectories: Bool
    ) throws -> FileTransferReport {
        let destinationURL = try hostURL(from: destinationPath)
        try prepareHostDirectoryDestination(
            destinationURL,
            overwrite: overwrite,
            createDirectories: createDirectories
        )

        let archiveURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).computer-use-\(UUID().uuidString).tar.gz")

        let download = try agentClient.startFileDownload(
            baseURL: baseURL,
            request: FileDownloadStartRequest(path: sourcePath, archiveFormat: .tarGzip)
        )

        let chunks = try downloadRemotePayload(
            baseURL: baseURL,
            download: download,
            destinationURL: archiveURL,
            chunkSize: chunkSize
        )

        do {
            _ = try agentClient.finishFileDownload(
                baseURL: baseURL,
                request: FileDownloadFinishRequest(downloadID: download.downloadID)
            )
            try extractHostDirectoryArchive(
                archiveURL,
                to: destinationURL,
                overwrite: overwrite
            )
            try? fileManager.removeItem(at: archiveURL)
        } catch {
            try? fileManager.removeItem(at: archiveURL)
            throw error
        }

        return FileTransferReport(
            direction: "pull",
            kind: "directory",
            machine: machineName,
            source: download.path,
            destination: destinationURL.path,
            bytes: download.bytes,
            sha256: download.sha256,
            chunks: chunks
        )
    }

    private func handleAction(arguments: [String]) throws -> String {
        guard let subcommand = arguments.first else {
            throw CLIError.missingSubcommand("action")
        }

        let flags = try FlagParser(arguments: Array(arguments.dropFirst())).parse()
        let name = try flags.requiredValue(for: "--machine")
        let baseURL = try agentBaseURL(forMachine: name)
        let app = flags.optionalValue(for: "--app")

        switch subcommand {
        case "click":
            return try JSONOutput.render(agentClient.click(
                baseURL: baseURL,
                request: ClickActionRequest(
                    target: try clickTarget(from: flags),
                    button: try mouseButton(from: flags.optionalValue(for: "--button")),
                    clickCount: try flags.optionalIntValue(for: "--click-count") ?? 1,
                    app: app
                )
            ))
        case "type":
            return try JSONOutput.render(agentClient.type(
                baseURL: baseURL,
                request: TypeActionRequest(text: try textValue(from: flags), app: app)
            ))
        case "key":
            return try JSONOutput.render(agentClient.key(
                baseURL: baseURL,
                request: try keyRequest(from: flags, app: app)
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
                    ),
                    app: app
                )
            ))
        case "scroll":
            return try JSONOutput.render(agentClient.scroll(
                baseURL: baseURL,
                request: ScrollActionRequest(
                    target: try elementReference(from: flags),
                    direction: try scrollDirection(from: flags.requiredValue(for: "--direction")),
                    pages: try flags.optionalDoubleValue(for: "--pages") ?? 1,
                    app: app
                )
            ))
        case "set-value":
            return try JSONOutput.render(agentClient.setValue(
                baseURL: baseURL,
                request: SetValueActionRequest(
                    target: try elementReference(from: flags),
                    value: try flags.requiredValue(for: "--value"),
                    app: app
                )
            ))
        case "action":
            return try JSONOutput.render(agentClient.perform(
                baseURL: baseURL,
                request: ElementActionRequest(
                    target: try elementReference(from: flags),
                    name: try flags.requiredValue(for: "--name"),
                    app: app
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
        let hasElement = flags.hasValue(for: "--snapshot-id")
            || flags.hasValue(for: "--element-id")
            || flags.hasValue(for: "--element-index")

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
                "click requires either --x/--y, --snapshot-id/--element-id, or --element-index"
            )
        }
    }

    private func elementReference(from flags: ParsedFlags) throws -> SnapshotElementReference {
        if let elementIndex = try flags.optionalIntValue(for: "--element-index") {
            return SnapshotElementReference(
                snapshotID: flags.optionalValue(for: "--snapshot-id"),
                elementIndex: elementIndex
            )
        }

        return SnapshotElementReference(
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
        if value == "middle" {
            return .center
        }

        guard let button = MouseButton(rawValue: value) else {
            throw CLIError.invalidFlagValue("--button", value)
        }

        return button
    }

    private func keyRequest(from flags: ParsedFlags, app: String?) throws -> KeyActionRequest {
        let rawValue = try flags.requiredValue(for: "--key")
        let parts = rawValue
            .split(separator: "+", omittingEmptySubsequences: false)
            .map(String.init)

        guard let rawKey = parts.last, rawKey.isEmpty == false else {
            throw CLIError.invalidFlagValue("--key", rawValue)
        }

        let modifiers = try parts.dropLast().map { try keyModifier(from: $0, rawValue: rawValue) }
        return KeyActionRequest(key: rawKey, modifiers: unique(modifiers), app: app)
    }

    private func keyModifier(from value: String, rawValue: String) throws -> KeyModifier {
        switch value.lowercased() {
        case "super", "cmd", "command", "meta":
            return .command
        case "shift":
            return .shift
        case "option", "alt":
            return .option
        case "control", "ctrl":
            return .control
        default:
            throw CLIError.invalidFlagValue("--key", rawValue)
        }
    }

    private func unique(_ modifiers: [KeyModifier]) -> [KeyModifier] {
        var seen = Set<KeyModifier>()
        var result: [KeyModifier] = []

        for modifier in modifiers where seen.insert(modifier).inserted {
            result.append(modifier)
        }

        return result
    }

    private func scrollDirection(from rawValue: String) throws -> ScrollDirection {
        guard let direction = ScrollDirection(rawValue: rawValue) else {
            throw CLIError.invalidFlagValue("--direction", rawValue)
        }

        return direction
    }

    private func fileChunkSize(from flags: ParsedFlags) throws -> Int {
        let chunkSize = try flags.optionalIntValue(for: "--chunk-size") ?? Self.defaultFileChunkSize
        guard chunkSize > 0 else {
            throw CLIError.invalidIntegerFlag("--chunk-size", "\(chunkSize)")
        }
        return chunkSize
    }

    private func hostURL(from path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw CLIError.missingValue("path")
        }

        if trimmed == "~" {
            return fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        }

        if trimmed.hasPrefix("~/") {
            return fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(String(trimmed.dropFirst(2)))
                .standardizedFileURL
        }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent(trimmed)
            .standardizedFileURL
    }

    private func hostItemKind(_ url: URL, flag: String) throws -> FileItemKind {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CLIError.fileTransferFailed("\(flag) does not exist: \(url.path)")
        }

        return isDirectory.boolValue ? .directory : .file
    }

    private func requireRegularHostPayload(_ url: URL) throws {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false
        else {
            throw CLIError.fileTransferFailed("transfer payload is not a regular file: \(url.path)")
        }
    }

    private func prepareHostDestination(
        _ url: URL,
        overwrite: Bool,
        createDirectories: Bool
    ) throws {
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue == false else {
                throw CLIError.fileTransferFailed("destination is a directory: \(url.path)")
            }
            guard overwrite else {
                throw CLIError.fileTransferFailed("destination already exists: \(url.path)")
            }
        }

        let parent = url.deletingLastPathComponent()
        if createDirectories {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        } else if fileManager.fileExists(atPath: parent.path) == false {
            throw CLIError.fileTransferFailed("destination parent does not exist: \(parent.path)")
        }
    }

    private func prepareHostDirectoryDestination(
        _ url: URL,
        overwrite: Bool,
        createDirectories: Bool
    ) throws {
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard overwrite else {
                throw CLIError.fileTransferFailed("destination already exists: \(url.path)")
            }
        }

        let parent = url.deletingLastPathComponent()
        if createDirectories {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        } else if fileManager.fileExists(atPath: parent.path) == false {
            throw CLIError.fileTransferFailed("destination parent does not exist: \(parent.path)")
        }
    }

    private func downloadRemotePayload(
        baseURL: URL,
        download: FileDownloadStartResponse,
        destinationURL: URL,
        chunkSize: Int
    ) throws -> Int {
        guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
            throw CLIError.fileTransferFailed("unable to create temporary destination \(destinationURL.path)")
        }

        var offset: Int64 = 0
        var chunks = 0
        var hasher = SHA256()
        let handle = try FileHandle(forWritingTo: destinationURL)

        do {
            while offset < download.bytes {
                let length = Int(min(Int64(chunkSize), download.bytes - offset))
                let response = try agentClient.downloadFileChunk(
                    baseURL: baseURL,
                    request: FileDownloadChunkRequest(
                        downloadID: download.downloadID,
                        offset: offset,
                        length: length
                    )
                )
                guard response.offset == offset else {
                    throw CLIError.fileTransferFailed("agent returned chunk offset \(response.offset), expected \(offset)")
                }
                guard let chunk = Data(base64Encoded: response.base64) else {
                    throw CLIError.fileTransferFailed("agent returned invalid chunk base64")
                }
                guard Int64(chunk.count) == response.bytes else {
                    throw CLIError.fileTransferFailed("agent returned inconsistent chunk byte count")
                }
                guard sha256Hex(chunk) == response.sha256 else {
                    throw CLIError.fileTransferFailed("agent returned chunk with invalid sha256")
                }

                try handle.write(contentsOf: chunk)
                hasher.update(data: chunk)
                offset += Int64(chunk.count)
                chunks += 1

                if response.eof && offset < download.bytes {
                    throw CLIError.fileTransferFailed("agent ended download before the expected byte count")
                }
            }

            try handle.close()

            let actualDigest = LocalFileDigest(bytes: offset, sha256: hex(hasher.finalize()))
            let expectedDigest = LocalFileDigest(bytes: download.bytes, sha256: download.sha256)
            try validateTransferDigest(
                FileTransferResponse(path: download.path, bytes: actualDigest.bytes, sha256: actualDigest.sha256),
                expected: expectedDigest
            )
            return chunks
        } catch {
            try? handle.close()
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    private func moveDownloadedFile(from tempURL: URL, to destinationURL: URL) throws {
        guard fileManager.fileExists(atPath: destinationURL.path) else {
            try fileManager.moveItem(at: tempURL, to: destinationURL)
            return
        }

        let backupURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).computer-use-backup-\(UUID().uuidString)")
        try fileManager.moveItem(at: destinationURL, to: backupURL)

        do {
            try fileManager.moveItem(at: tempURL, to: destinationURL)
            try? fileManager.removeItem(at: backupURL)
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path) == false {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }
            throw error
        }
    }

    private func createHostDirectoryArchive(_ sourceURL: URL) throws -> URL {
        let archiveURL = fileManager.temporaryDirectory
            .appendingPathComponent("computer-use-\(UUID().uuidString).tar.gz")
        try runHostTool(executable: "/usr/bin/tar", arguments: [
            "-C", sourceURL.path,
            "-czf", archiveURL.path,
            ".",
        ])
        return archiveURL
    }

    private func extractHostDirectoryArchive(
        _ archiveURL: URL,
        to destinationURL: URL,
        overwrite: Bool
    ) throws {
        let backupURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).computer-use-backup-\(UUID().uuidString)")
        let hadExistingDestination = fileManager.fileExists(atPath: destinationURL.path)

        if hadExistingDestination {
            guard overwrite else {
                throw CLIError.fileTransferFailed("destination already exists: \(destinationURL.path)")
            }
            try fileManager.moveItem(at: destinationURL, to: backupURL)
        }

        do {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            try runHostTool(executable: "/usr/bin/tar", arguments: [
                "-xzf", archiveURL.path,
                "-C", destinationURL.path,
            ])
            if hadExistingDestination {
                try? fileManager.removeItem(at: backupURL)
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if hadExistingDestination {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }
            throw error
        }
    }

    private func runHostTool(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(
                decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw CLIError.fileTransferFailed(
                "\(executable) exited with code \(process.terminationStatus): \(stderr)"
            )
        }
    }

    private func fileDigest(at url: URL) throws -> LocalFileDigest {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        var bytes: Int64 = 0

        while let data = try handle.read(upToCount: 1024 * 1024), data.isEmpty == false {
            hasher.update(data: data)
            bytes += Int64(data.count)
        }

        return LocalFileDigest(bytes: bytes, sha256: hex(hasher.finalize()))
    }

    private func validateTransferDigest(
        _ response: FileTransferResponse,
        expected: LocalFileDigest
    ) throws {
        guard response.bytes == expected.bytes else {
            throw CLIError.fileTransferFailed(
                "transfer returned \(response.bytes) bytes, expected \(expected.bytes)"
            )
        }
        guard response.sha256 == expected.sha256 else {
            throw CLIError.fileTransferFailed(
                "transfer sha256 \(response.sha256), expected \(expected.sha256)"
            )
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    private func hex<Digest: Sequence>(_ digest: Digest) -> String where Digest.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
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
          computer-use runtime info
          computer-use runtime bootstrap
          computer-use runtime container -- <container-args...>
          computer-use agent ping --machine <name>
          computer-use agent doctor --machine <name>
          computer-use permissions get --machine <name>
          computer-use permissions request --machine <name>
          computer-use apps list --machine <name>
          computer-use state get --machine <name> [--app <name-or-bundle-id> | --bundle-id <bundle-id>]
          computer-use files push --machine <name> --src <host-file-or-directory> --dest <guest-path> [--chunk-size <bytes>] [--overwrite <true|false>] [--create-directories <true|false>]
          computer-use files pull --machine <name> --src <guest-file-or-directory> --dest <host-path> [--chunk-size <bytes>] [--overwrite <true|false>] [--create-directories <true|false>]
          computer-use action click --machine <name> [--app <app>] (--x <x> --y <y> | --snapshot-id <id> --element-id <id> | [--snapshot-id <id>] --element-index <n>)
          computer-use action type --machine <name> [--app <app>] --text <text>
          computer-use action key --machine <name> [--app <app>] --key <key-or-combo>
          computer-use action drag --machine <name> [--app <app>] --from-x <x> --from-y <y> --to-x <x> --to-y <y>
          computer-use action scroll --machine <name> [--app <app>] ([--snapshot-id <id>] --element-index <n> | --snapshot-id <id> --element-id <id>) --direction <up|down|left|right> [--pages <n>]
          computer-use action set-value --machine <name> [--app <app>] ([--snapshot-id <id>] --element-index <n> | --snapshot-id <id> --element-id <id>) --value <value>
          computer-use action action --machine <name> [--app <app>] ([--snapshot-id <id>] --element-index <n> | --snapshot-id <id> --element-id <id>) --name <AXAction>
        """
    }

    private static func runtimeRestartPrompt(for error: ContainerBridgeError) -> String {
        switch error {
        case let .runtimeRootMismatch(expectedAppRoot, expectedInstallRoot, actualAppRoot, actualInstallRoot):
            """
            container services are already running with a different root.
              expected app root: \(expectedAppRoot)
              expected install root: \(expectedInstallRoot)
              actual app root: \(actualAppRoot ?? "<unknown>")
              actual install root: \(actualInstallRoot ?? "<unknown>")
            Restart container services for this runtime and retry machine start? This stops currently running container services. [y/N]
            """ + " "
        default:
            "Restart container services for this runtime and retry machine start? [y/N] "
        }
    }

    private static func writeStandardError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }
}

public struct ContainerRuntimeReport: Encodable, Equatable, Sendable {
    public let version: String
    public let root: String
    public let appRoot: String
    public let installRoot: String
    public let executable: String
    public let releasePackageURL: String
    public let bootstrapped: Bool?

    public init(layout: ContainerRuntimeLayout, bootstrapped: Bool?) {
        self.version = layout.version
        self.root = layout.root.path
        self.appRoot = layout.appRoot.path
        self.installRoot = layout.installRoot.path
        self.executable = layout.executableURL.path
        self.releasePackageURL = layout.releasePackageURL.absoluteString
        self.bootstrapped = bootstrapped
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case root
        case appRoot = "app_root"
        case installRoot = "install_root"
        case executable
        case releasePackageURL = "release_package_url"
        case bootstrapped
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

public struct FileTransferReport: Encodable, Equatable, Sendable {
    public let direction: String
    public let kind: String
    public let machine: String
    public let source: String
    public let destination: String
    public let bytes: Int64
    public let sha256: String
    public let chunks: Int

    public init(
        direction: String,
        kind: String,
        machine: String,
        source: String,
        destination: String,
        bytes: Int64,
        sha256: String,
        chunks: Int
    ) {
        self.direction = direction
        self.kind = kind
        self.machine = machine
        self.source = source
        self.destination = destination
        self.bytes = bytes
        self.sha256 = sha256
        self.chunks = chunks
    }
}

private struct LocalFileDigest: Equatable {
    let bytes: Int64
    let sha256: String
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

    func optionalDoubleValue(for key: String) throws -> Double? {
        guard let rawValue = values[key] else {
            return nil
        }

        guard let value = Double(rawValue) else {
            throw CLIError.invalidDoubleFlag(key, rawValue)
        }

        return value
    }

    func optionalBoolValue(for key: String) throws -> Bool? {
        guard let rawValue = values[key] else {
            return nil
        }

        switch rawValue.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            throw CLIError.invalidFlagValue(key, rawValue)
        }
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
    case fileTransferFailed(String)

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
        case let .fileTransferFailed(message):
            message
        }
    }
}

private extension ContainerBridgeError {
    var isRuntimeRootMismatch: Bool {
        guard case .runtimeRootMismatch = self else {
            return false
        }
        return true
    }
}
