import AppKit
import ApplicationServices
import Foundation

public struct RunningApplication: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var processIdentifier: Int32
    public var isFrontmost: Bool
    public var isRunning: Bool
    public var lastUsed: Date?
    public var useCount: Int?

    public init(
        bundleIdentifier: String,
        name: String,
        processIdentifier: Int32,
        isFrontmost: Bool,
        isRunning: Bool = true,
        lastUsed: Date? = nil,
        useCount: Int? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.processIdentifier = processIdentifier
        self.isFrontmost = isFrontmost
        self.isRunning = isRunning
        self.lastUsed = lastUsed
        self.useCount = useCount
    }
}

public protocol RunningApplicationListing: Sendable {
    func runningApplications() async throws -> [RunningApplication]
}

public protocol ApplicationActivating: Sendable {
    func activateApplication(target: String) async throws -> RunningApplication
}

public protocol ApplicationUsageTracking: Sendable {
    func recordUsage(application: RunningApplication) throws -> RunningApplication
    func applicationsByMergingUsage(with runningApplications: [RunningApplication]) throws -> [RunningApplication]
}

public enum ApplicationActivationError: Error, LocalizedError, Equatable, Sendable {
    case appNotFound(String)
    case appAmbiguous(target: String, candidates: [RunningApplication])
    case appLaunchFailed(String)
    case appWindowUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .appNotFound(target):
            "application \(target) was not found"
        case let .appAmbiguous(target, candidates):
            "application \(target) matched multiple candidates: \(candidates.map(\.bundleIdentifier).joined(separator: ", "))"
        case let .appLaunchFailed(target):
            "application \(target) could not be launched"
        case let .appWindowUnavailable(target):
            "application \(target) did not expose a key window"
        }
    }
}

public struct ApplicationResolver: Sendable {
    public init() {}

    public func resolve(
        target: String,
        applications: [RunningApplication]
    ) throws -> RunningApplication? {
        let normalizedTarget = normalized(target)
        let matches = applications.filter { application in
            normalized(application.bundleIdentifier) == normalizedTarget
                || normalized(application.name) == normalizedTarget
        }

        if matches.count > 1 {
            throw ApplicationActivationError.appAmbiguous(target: target, candidates: matches)
        }

        return matches.first
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
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

public struct WorkspaceApplicationActivator: ApplicationActivating {
    private let applicationLister: any RunningApplicationListing
    private let resolver: ApplicationResolver
    private let pollIntervalNanoseconds: UInt64
    private let maxPolls: Int

    public init(
        applicationLister: any RunningApplicationListing = WorkspaceRunningApplicationLister(),
        resolver: ApplicationResolver = ApplicationResolver(),
        pollIntervalNanoseconds: UInt64 = 200_000_000,
        maxPolls: Int = 25
    ) {
        self.applicationLister = applicationLister
        self.resolver = resolver
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxPolls = maxPolls
    }

    public func activateApplication(target: String) async throws -> RunningApplication {
        let normalizedTarget = normalized(target)
        let applications = try await applicationLister.runningApplications()

        if let runningApplication = try resolver.resolve(target: target, applications: applications) {
            try activate(runningApplication)
            return try await waitForReadyApplication(target: normalizedTarget) ?? runningApplication
        }

        guard let applicationURL = applicationURL(for: target) else {
            throw ApplicationActivationError.appNotFound(target)
        }

        let launchedApplication = try await launch(applicationURL: applicationURL, target: target)
        if let launchedApplication {
            return try await waitForReadyApplication(target: normalizedTarget) ?? runningApplication(launchedApplication)
        }

        throw ApplicationActivationError.appLaunchFailed(target)
    }

    private func activate(_ application: RunningApplication) throws {
        guard let runningApplication = NSRunningApplication(processIdentifier: application.processIdentifier) else {
            throw ApplicationActivationError.appNotFound(application.bundleIdentifier)
        }

        runningApplication.activate(options: [.activateAllWindows])
    }

    private func launch(applicationURL: URL, target: String) async throws -> NSRunningApplication? {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: application)
                }
            }
        }
    }

    private func waitForReadyApplication(target: String) async throws -> RunningApplication? {
        var activeApplication: RunningApplication?

        for _ in 0..<maxPolls {
            let applications = try await applicationLister.runningApplications()
            if let active = try resolver.resolve(target: target, applications: applications),
               active.isFrontmost {
                activeApplication = active
                if hasKeyWindow(processIdentifier: active.processIdentifier) {
                    return active
                }
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        return activeApplication
    }

    private func hasKeyWindow(processIdentifier: Int32) -> Bool {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success, focusedWindow != nil {
            return true
        }

        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &windows
        ) == .success,
              let windowList = windows as? [AXUIElement] else {
            return false
        }

        return windowList.isEmpty == false
    }

    private func applicationURL(for target: String) -> URL? {
        if target.contains("."),
           let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
            return bundleURL
        }

        for directory in applicationSearchDirectories() {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator
                where url.pathExtension == "app"
                    && normalized(url.deletingPathExtension().lastPathComponent) == normalized(target) {
                return url
            }
        }

        return nil
    }

    private func applicationSearchDirectories() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }

    private func runningApplication(_ application: NSRunningApplication) -> RunningApplication {
        RunningApplication(
            bundleIdentifier: application.bundleIdentifier ?? "",
            name: application.localizedName ?? application.bundleIdentifier ?? "Unknown",
            processIdentifier: application.processIdentifier,
            isFrontmost: application.isActive
        )
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public final class FileApplicationUsageStore: ApplicationUsageTracking, @unchecked Sendable {
    public struct ApplicationUsageRecord: Codable, Equatable, Sendable {
        public var bundleIdentifier: String
        public var name: String
        public var lastUsed: Date
        public var useCount: Int

        public init(
            bundleIdentifier: String,
            name: String,
            lastUsed: Date,
            useCount: Int
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.name = name
            self.lastUsed = lastUsed
            self.useCount = useCount
        }
    }

    private struct Payload: Codable {
        var records: [ApplicationUsageRecord]
    }

    private let url: URL
    private let now: @Sendable () -> Date
    private let retention: TimeInterval
    private let lock = NSLock()

    public init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/computer-use-cli/app-usage.json"),
        now: @escaping @Sendable () -> Date = Date.init,
        retention: TimeInterval = 14 * 24 * 60 * 60
    ) {
        self.url = url
        self.now = now
        self.retention = retention
    }

    public func recordUsage(application: RunningApplication) throws -> RunningApplication {
        guard application.bundleIdentifier.isEmpty == false else {
            return application
        }

        lock.lock()
        defer {
            lock.unlock()
        }

        let timestamp = now()
        var records = try loadRecordsLocked(referenceDate: timestamp)
        let useCount = (records[application.bundleIdentifier]?.useCount ?? 0) + 1
        records[application.bundleIdentifier] = ApplicationUsageRecord(
            bundleIdentifier: application.bundleIdentifier,
            name: application.name,
            lastUsed: timestamp,
            useCount: useCount
        )
        try saveRecordsLocked(records)

        var updated = application
        updated.isRunning = true
        updated.lastUsed = timestamp
        updated.useCount = useCount
        return updated
    }

    public func applicationsByMergingUsage(
        with runningApplications: [RunningApplication]
    ) throws -> [RunningApplication] {
        lock.lock()
        defer {
            lock.unlock()
        }

        let records = try loadRecordsLocked(referenceDate: now())
        var seenBundleIdentifiers = Set<String>()
        var merged = runningApplications.map { application in
            var application = application
            application.isRunning = true
            if let record = records[application.bundleIdentifier] {
                application.lastUsed = record.lastUsed
                application.useCount = record.useCount
            }
            seenBundleIdentifiers.insert(application.bundleIdentifier)
            return application
        }

        let recentApplications = records.values
            .filter { seenBundleIdentifiers.contains($0.bundleIdentifier) == false }
            .sorted { lhs, rhs in lhs.lastUsed > rhs.lastUsed }
            .map { record in
                RunningApplication(
                    bundleIdentifier: record.bundleIdentifier,
                    name: record.name,
                    processIdentifier: 0,
                    isFrontmost: false,
                    isRunning: false,
                    lastUsed: record.lastUsed,
                    useCount: record.useCount
                )
            }

        merged.append(contentsOf: recentApplications)
        return merged
    }

    private func loadRecordsLocked(referenceDate: Date) throws -> [String: ApplicationUsageRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let cutoff = referenceDate.addingTimeInterval(-retention)
        return Dictionary(
            uniqueKeysWithValues: payload.records
                .filter { $0.lastUsed >= cutoff }
                .map { ($0.bundleIdentifier, $0) }
        )
    }

    private func saveRecordsLocked(_ records: [String: ApplicationUsageRecord]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let payload = Payload(records: records.values.sorted { lhs, rhs in
            lhs.lastUsed > rhs.lastUsed
        })
        try encoder.encode(payload).write(to: url, options: [.atomic])
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
