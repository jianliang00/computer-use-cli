import AppKit
import Foundation

public struct RunningApplication: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var processIdentifier: Int32
    public var isFrontmost: Bool

    public init(
        bundleIdentifier: String,
        name: String,
        processIdentifier: Int32,
        isFrontmost: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.processIdentifier = processIdentifier
        self.isFrontmost = isFrontmost
    }
}

public protocol RunningApplicationListing: Sendable {
    func runningApplications() async throws -> [RunningApplication]
}

public struct WorkspaceRunningApplicationLister: RunningApplicationListing {
    private let processTableLister: ProcessTableApplicationLister

    public init() {
        self.processTableLister = ProcessTableApplicationLister()
    }

    public func runningApplications() async throws -> [RunningApplication] {
        let workspaceApplications = NSWorkspace.shared.runningApplications
            .filter { application in
                application.activationPolicy != .prohibited
            }
            .map { application in
                RunningApplication(
                    bundleIdentifier: application.bundleIdentifier ?? "",
                    name: application.localizedName ?? application.bundleIdentifier ?? "Unknown",
                    processIdentifier: application.processIdentifier,
                    isFrontmost: application.isActive
                )
            }
            .filter { application in
                application.bundleIdentifier.isEmpty == false || application.name != "Unknown"
            }

        return processTableLister
            .mergeApplications(
                workspaceApplications,
                frontmostProcessIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier
            )
            .sorted { lhs, rhs in
                if lhs.isFrontmost != rhs.isFrontmost {
                    return lhs.isFrontmost
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    init(processTableLister: ProcessTableApplicationLister) {
        self.processTableLister = processTableLister
    }
}

struct ProcessTableApplication: Equatable, Sendable {
    var processIdentifier: Int32
    var executablePath: String

    init(processIdentifier: Int32, executablePath: String) {
        self.processIdentifier = processIdentifier
        self.executablePath = executablePath
    }
}

struct ProcessTableApplicationLister: Sendable {
    typealias ProcessProvider = @Sendable () -> [ProcessTableApplication]

    private let processProvider: ProcessProvider

    init(processProvider: @escaping ProcessProvider = ProcessTableApplicationLister.defaultProcesses) {
        self.processProvider = processProvider
    }

    func mergeApplications(
        _ applications: [RunningApplication],
        frontmostProcessIdentifier: Int32?
    ) -> [RunningApplication] {
        var merged = applications
        var seenProcessIdentifiers = Set(applications.map(\.processIdentifier))

        for process in processProvider() where seenProcessIdentifiers.contains(process.processIdentifier) == false {
            guard let application = runningApplication(
                for: process,
                frontmostProcessIdentifier: frontmostProcessIdentifier
            ) else {
                continue
            }

            merged.append(application)
            seenProcessIdentifiers.insert(process.processIdentifier)
        }

        return merged
    }

    private func runningApplication(
        for process: ProcessTableApplication,
        frontmostProcessIdentifier: Int32?
    ) -> RunningApplication? {
        guard let bundleURL = appBundleURL(forExecutablePath: process.executablePath),
              let bundle = Bundle(url: bundleURL),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier.isEmpty == false
        else {
            return nil
        }

        return RunningApplication(
            bundleIdentifier: bundleIdentifier,
            name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? bundleURL.deletingPathExtension().lastPathComponent,
            processIdentifier: process.processIdentifier,
            isFrontmost: process.processIdentifier == frontmostProcessIdentifier
        )
    }

    private func appBundleURL(forExecutablePath executablePath: String) -> URL? {
        let marker = ".app/Contents/MacOS/"
        guard let range = executablePath.range(of: marker, options: [.caseInsensitive]) else {
            return nil
        }

        let bundlePath = String(executablePath[..<range.lowerBound]) + ".app"
        guard FileManager.default.fileExists(atPath: bundlePath) else {
            return nil
        }

        return URL(fileURLWithPath: bundlePath)
    }

    private static func defaultProcesses() -> [ProcessTableApplication] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else {
            return []
        }

        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap(processTableApplication)
    }

    private static func processTableApplication(_ line: Substring) -> ProcessTableApplication? {
        let parts = line
            .trimmingCharacters(in: .whitespaces)
            .split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.count == 2,
              let processIdentifier = Int32(parts[0])
        else {
            return nil
        }

        return ProcessTableApplication(
            processIdentifier: processIdentifier,
            executablePath: String(parts[1])
        )
    }
}
