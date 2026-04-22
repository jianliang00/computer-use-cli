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
