import Foundation

enum JSONOutput {
    static func render<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }

        return string
    }
}
