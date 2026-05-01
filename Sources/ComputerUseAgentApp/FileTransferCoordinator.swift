import AgentProtocol
import CryptoKit
import Foundation

final class FileTransferCoordinator: @unchecked Sendable {
    private let homeDirectory: URL
    private let temporaryDirectory: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var uploadSessions: [String: UploadSession] = [:]
    private var downloadSessions: [String: DownloadSession] = [:]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.temporaryDirectory = temporaryDirectory.standardizedFileURL
        self.fileManager = fileManager
    }

    func stat(_ request: FileStatRequest) throws -> FileStatResponse {
        let url = try resolvedGuestURL(for: request.path)
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FileTransferCoordinatorError.notFound(url.path)
        }

        if isDirectory.boolValue {
            return FileStatResponse(path: url.path, kind: .directory)
        }

        let digest = try fileDigest(at: url)
        return FileStatResponse(
            path: url.path,
            kind: .file,
            bytes: digest.bytes,
            sha256: digest.sha256
        )
    }

    func startUpload(_ request: FileUploadStartRequest) throws -> FileUploadStartResponse {
        guard request.expectedBytes.map({ $0 >= 0 }) ?? true else {
            throw FileTransferCoordinatorError.invalidRequest("expected_bytes must be non-negative")
        }

        let destinationURL = try resolvedGuestURL(for: request.path)
        if request.archiveFormat == nil && existingDirectory(at: destinationURL) {
            throw FileTransferCoordinatorError.unsupportedDirectory(destinationURL.path)
        }
        if fileManager.fileExists(atPath: destinationURL.path), request.overwrite == false {
            throw FileTransferCoordinatorError.destinationExists(destinationURL.path)
        }

        let transferDirectory = try ensureTransferDirectory()
        let uploadID = UUID().uuidString
        let tempURL = transferDirectory.appendingPathComponent("\(uploadID).upload")
        guard fileManager.createFile(atPath: tempURL.path, contents: nil) else {
            throw FileTransferCoordinatorError.invalidRequest("unable to create upload session")
        }

        let session = UploadSession(
            id: uploadID,
            destinationURL: destinationURL,
            tempURL: tempURL,
            expectedBytes: request.expectedBytes,
            expectedSHA256: request.sha256,
            overwrite: request.overwrite,
            createDirectories: request.createDirectories,
            archiveFormat: request.archiveFormat,
            receivedBytes: 0
        )

        lock.withLock {
            uploadSessions[uploadID] = session
        }

        return FileUploadStartResponse(uploadID: uploadID, path: destinationURL.path)
    }

    func appendUploadChunk(_ request: FileUploadChunkRequest) throws -> FileUploadChunkResponse {
        guard request.offset >= 0 else {
            throw FileTransferCoordinatorError.invalidRequest("offset must be non-negative")
        }
        guard let chunk = Data(base64Encoded: request.base64) else {
            throw FileTransferCoordinatorError.invalidRequest("chunk base64 is invalid")
        }
        if let expectedSHA256 = request.sha256 {
            let actualSHA256 = sha256Hex(chunk)
            guard expectedSHA256 == actualSHA256 else {
                throw FileTransferCoordinatorError.checksumMismatch(
                    expected: expectedSHA256,
                    actual: actualSHA256
                )
            }
        }

        let updatedSession = try lock.withLock {
            guard var session = uploadSessions[request.uploadID] else {
                throw FileTransferCoordinatorError.sessionNotFound(request.uploadID)
            }
            guard request.offset == session.receivedBytes else {
                throw FileTransferCoordinatorError.invalidRequest(
                    "chunk offset \(request.offset) does not match received byte count \(session.receivedBytes)"
                )
            }

            let handle = try FileHandle(forWritingTo: session.tempURL)
            defer {
                try? handle.close()
            }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: chunk)

            session.receivedBytes += Int64(chunk.count)
            uploadSessions[request.uploadID] = session
            return session
        }

        return FileUploadChunkResponse(
            uploadID: request.uploadID,
            offset: request.offset,
            bytes: Int64(chunk.count),
            receivedBytes: updatedSession.receivedBytes
        )
    }

    func finishUpload(_ request: FileUploadFinishRequest) throws -> FileTransferResponse {
        let session = try lock.withLock {
            guard let session = uploadSessions.removeValue(forKey: request.uploadID) else {
                throw FileTransferCoordinatorError.sessionNotFound(request.uploadID)
            }
            return session
        }

        do {
            let digest = try fileDigest(at: session.tempURL)
            if let expectedBytes = session.expectedBytes, expectedBytes != digest.bytes {
                throw FileTransferCoordinatorError.sizeMismatch(
                    expected: expectedBytes,
                    actual: digest.bytes
                )
            }
            if let expectedSHA256 = session.expectedSHA256, expectedSHA256 != digest.sha256 {
                throw FileTransferCoordinatorError.checksumMismatch(
                    expected: expectedSHA256,
                    actual: digest.sha256
                )
            }

            let parentURL = session.destinationURL.deletingLastPathComponent()
            if session.createDirectories {
                try fileManager.createDirectory(
                    at: parentURL,
                    withIntermediateDirectories: true
                )
            } else if fileManager.fileExists(atPath: parentURL.path) == false {
                throw FileTransferCoordinatorError.notFound(parentURL.path)
            }

            switch session.archiveFormat {
            case .none:
                if existingDirectory(at: session.destinationURL) {
                    throw FileTransferCoordinatorError.unsupportedDirectory(session.destinationURL.path)
                }
                try moveUploadedFile(session)
            case .tarGzip:
                try extractUploadedArchive(session)
            }

            return FileTransferResponse(
                path: session.destinationURL.path,
                bytes: digest.bytes,
                sha256: digest.sha256
            )
        } catch {
            try? fileManager.removeItem(at: session.tempURL)
            throw error
        }
    }

    func startDownload(_ request: FileDownloadStartRequest) throws -> FileDownloadStartResponse {
        let sourceURL = try resolvedGuestURL(for: request.path)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FileTransferCoordinatorError.notFound(sourceURL.path)
        }

        let sourceIsDirectory = existingDirectory(at: sourceURL)
        let downloadURL: URL
        let cleanupURL: URL?
        switch request.archiveFormat {
        case .none:
            if sourceIsDirectory {
                throw FileTransferCoordinatorError.unsupportedDirectory(sourceURL.path)
            }
            downloadURL = sourceURL
            cleanupURL = nil
        case .tarGzip:
            guard sourceIsDirectory else {
                throw FileTransferCoordinatorError.invalidRequest("archive downloads require a directory source")
            }
            downloadURL = try createDirectoryArchive(sourceURL)
            cleanupURL = downloadURL
        }

        if existingDirectory(at: downloadURL) {
            throw FileTransferCoordinatorError.unsupportedDirectory(sourceURL.path)
        }

        let digest = try fileDigest(at: downloadURL)
        let downloadID = UUID().uuidString
        let session = DownloadSession(
            id: downloadID,
            sourceURL: downloadURL,
            publicPath: sourceURL.path,
            bytes: digest.bytes,
            sha256: digest.sha256,
            cleanupURL: cleanupURL
        )

        lock.withLock {
            downloadSessions[downloadID] = session
        }

        return FileDownloadStartResponse(
            downloadID: downloadID,
            path: sourceURL.path,
            bytes: digest.bytes,
            sha256: digest.sha256
        )
    }

    func readDownloadChunk(_ request: FileDownloadChunkRequest) throws -> FileDownloadChunkResponse {
        guard request.offset >= 0 else {
            throw FileTransferCoordinatorError.invalidRequest("offset must be non-negative")
        }
        guard request.length > 0 else {
            throw FileTransferCoordinatorError.invalidRequest("length must be positive")
        }

        let session = try lock.withLock {
            guard let session = downloadSessions[request.downloadID] else {
                throw FileTransferCoordinatorError.sessionNotFound(request.downloadID)
            }
            return session
        }

        guard request.offset <= session.bytes else {
            throw FileTransferCoordinatorError.invalidRequest(
                "offset \(request.offset) is past file size \(session.bytes)"
            )
        }

        let remainingBytes = session.bytes - request.offset
        let length = min(Int64(request.length), remainingBytes)
        let chunk: Data
        if length == 0 {
            chunk = Data()
        } else {
            let handle = try FileHandle(forReadingFrom: session.sourceURL)
            defer {
                try? handle.close()
            }
            try handle.seek(toOffset: UInt64(request.offset))
            chunk = try handle.read(upToCount: Int(length)) ?? Data()
        }

        return FileDownloadChunkResponse(
            downloadID: request.downloadID,
            offset: request.offset,
            base64: chunk.base64EncodedString(),
            bytes: Int64(chunk.count),
            sha256: sha256Hex(chunk),
            eof: request.offset + Int64(chunk.count) >= session.bytes
        )
    }

    func finishDownload(_ request: FileDownloadFinishRequest) throws -> ActionResponse {
        let session = try lock.withLock {
            guard let session = downloadSessions.removeValue(forKey: request.downloadID) else {
                throw FileTransferCoordinatorError.sessionNotFound(request.downloadID)
            }
            return session
        }

        if let cleanupURL = session.cleanupURL {
            try? fileManager.removeItem(at: cleanupURL)
        }

        return ActionResponse()
    }

    private func ensureTransferDirectory() throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent(
            "computer-use-file-transfers",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func resolvedGuestURL(for path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw FileTransferCoordinatorError.invalidRequest("path is required")
        }

        let url: URL
        if trimmed == "~" {
            url = homeDirectory
        } else if trimmed.hasPrefix("~/") {
            url = homeDirectory.appendingPathComponent(String(trimmed.dropFirst(2)))
        } else if trimmed.hasPrefix("/") {
            url = URL(fileURLWithPath: trimmed)
        } else {
            url = homeDirectory.appendingPathComponent(trimmed)
        }

        let standardized = url.standardizedFileURL
        guard isAllowedGuestURL(standardized) else {
            throw FileTransferCoordinatorError.pathOutsideAllowedRoots(standardized.path)
        }
        return standardized
    }

    private func isAllowedGuestURL(_ url: URL) -> Bool {
        let path = url.path
        let homePath = homeDirectory.path

        return path == homePath
            || path.hasPrefix(homePath + "/")
            || path == "/tmp"
            || path.hasPrefix("/tmp/")
            || path == "/private/tmp"
            || path.hasPrefix("/private/tmp/")
    }

    private func existingDirectory(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func moveUploadedFile(_ session: UploadSession) throws {
        guard fileManager.fileExists(atPath: session.destinationURL.path) else {
            try fileManager.moveItem(at: session.tempURL, to: session.destinationURL)
            return
        }

        guard session.overwrite else {
            throw FileTransferCoordinatorError.destinationExists(session.destinationURL.path)
        }

        let backupURL = session.destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(session.destinationURL.lastPathComponent).computer-use-backup-\(UUID().uuidString)")
        try fileManager.moveItem(at: session.destinationURL, to: backupURL)

        do {
            try fileManager.moveItem(at: session.tempURL, to: session.destinationURL)
            try? fileManager.removeItem(at: backupURL)
        } catch {
            if fileManager.fileExists(atPath: session.destinationURL.path) == false {
                try? fileManager.moveItem(at: backupURL, to: session.destinationURL)
            }
            throw error
        }
    }

    private func extractUploadedArchive(_ session: UploadSession) throws {
        let backupURL = session.destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(session.destinationURL.lastPathComponent).computer-use-backup-\(UUID().uuidString)")
        let hadExistingDestination = fileManager.fileExists(atPath: session.destinationURL.path)

        if hadExistingDestination {
            guard session.overwrite else {
                throw FileTransferCoordinatorError.destinationExists(session.destinationURL.path)
            }
            try fileManager.moveItem(at: session.destinationURL, to: backupURL)
        }

        do {
            try fileManager.createDirectory(at: session.destinationURL, withIntermediateDirectories: true)
            try runTar(arguments: [
                "-xzf", session.tempURL.path,
                "-C", session.destinationURL.path,
            ])
            try? fileManager.removeItem(at: session.tempURL)
            if hadExistingDestination {
                try? fileManager.removeItem(at: backupURL)
            }
        } catch {
            try? fileManager.removeItem(at: session.destinationURL)
            if hadExistingDestination {
                try? fileManager.moveItem(at: backupURL, to: session.destinationURL)
            }
            throw error
        }
    }

    private func createDirectoryArchive(_ sourceURL: URL) throws -> URL {
        let transferDirectory = try ensureTransferDirectory()
        let archiveURL = transferDirectory.appendingPathComponent("\(UUID().uuidString).tar.gz")
        try runTar(arguments: [
            "-C", sourceURL.path,
            "-czf", archiveURL.path,
            ".",
        ])
        return archiveURL
    }

    private func runTar(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
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
            throw FileTransferCoordinatorError.invalidRequest(
                "tar failed with exit code \(process.terminationStatus): \(stderr)"
            )
        }
    }

    private func fileDigest(at url: URL) throws -> FileDigest {
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

        return FileDigest(bytes: bytes, sha256: hex(hasher.finalize()))
    }

    private func sha256Hex(_ data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    private func hex<Digest: Sequence>(_ digest: Digest) -> String where Digest.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum FileTransferCoordinatorError: Error, LocalizedError, Equatable {
    case invalidRequest(String)
    case pathOutsideAllowedRoots(String)
    case notFound(String)
    case destinationExists(String)
    case unsupportedDirectory(String)
    case sessionNotFound(String)
    case checksumMismatch(expected: String, actual: String)
    case sizeMismatch(expected: Int64, actual: Int64)

    var errorDescription: String? {
        switch self {
        case let .invalidRequest(message):
            message
        case let .pathOutsideAllowedRoots(path):
            "file transfer path is outside the allowed guest roots: \(path)"
        case let .notFound(path):
            "file was not found: \(path)"
        case let .destinationExists(path):
            "destination already exists: \(path)"
        case let .unsupportedDirectory(path):
            "directory transfer is not supported for this path: \(path)"
        case let .sessionNotFound(id):
            "file transfer session was not found: \(id)"
        case let .checksumMismatch(expected, actual):
            "sha256 mismatch: expected \(expected), got \(actual)"
        case let .sizeMismatch(expected, actual):
            "size mismatch: expected \(expected), got \(actual)"
        }
    }
}

private struct UploadSession: Equatable {
    var id: String
    var destinationURL: URL
    var tempURL: URL
    var expectedBytes: Int64?
    var expectedSHA256: String?
    var overwrite: Bool
    var createDirectories: Bool
    var archiveFormat: FileArchiveFormat?
    var receivedBytes: Int64
}

private struct DownloadSession: Equatable {
    var id: String
    var sourceURL: URL
    var publicPath: String
    var bytes: Int64
    var sha256: String
    var cleanupURL: URL?
}

private struct FileDigest: Equatable {
    var bytes: Int64
    var sha256: String
}

private extension NSLock {
    func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        lock()
        defer {
            unlock()
        }
        return try body()
    }
}
