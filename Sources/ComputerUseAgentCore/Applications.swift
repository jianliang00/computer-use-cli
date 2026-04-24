import AppKit

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
    public init() {}

    public func runningApplications() async throws -> [RunningApplication] {
        NSWorkspace.shared.runningApplications
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
            .sorted { lhs, rhs in
                if lhs.isFrontmost != rhs.isFrontmost {
                    return lhs.isFrontmost
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
