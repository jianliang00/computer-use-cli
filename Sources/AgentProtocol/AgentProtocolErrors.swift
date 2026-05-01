import Foundation

public struct AgentErrorCode: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let permissionDenied: Self = "permission_denied"
    public static let snapshotExpired: Self = "snapshot_expired"
    public static let invalidRequest: Self = "invalid_request"
    public static let appNotFound: Self = "app_not_found"
    public static let appAmbiguous: Self = "app_ambiguous"
    public static let elementNotFound: Self = "element_not_found"
    public static let unsupportedAction: Self = "unsupported_action"
    public static let fileTransferFailed: Self = "file_transfer_failed"
}

public struct AgentError: Codable, Sendable, Equatable {
    public var code: AgentErrorCode
    public var message: String

    public init(code: AgentErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public struct ErrorResponse: Codable, Sendable, Equatable {
    public var error: AgentError

    public init(error: AgentError) {
        self.error = error
    }
}
