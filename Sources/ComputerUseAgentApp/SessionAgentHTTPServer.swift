import Foundation
import Network

public final class SessionAgentHTTPServer: @unchecked Sendable {
    private let configuration: SessionAgentConfiguration
    private let router: SessionAgentHTTPRouter
    private var listener: NWListener?

    public init(
        configuration: SessionAgentConfiguration = .guestDefault,
        router: SessionAgentHTTPRouter
    ) {
        self.configuration = configuration
        self.router = router
    }

    public func start(queue: DispatchQueue = .main) throws {
        let port = UInt16(exactly: configuration.port).flatMap(NWEndpoint.Port.init(rawValue:))
        guard let port else {
            throw SessionAgentHTTPServerError.invalidPort(configuration.port)
        }

        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [router] (connection: NWConnection) in
            connection.start(queue: queue)
            Self.receive(on: connection, router: router, buffer: Data())
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private static func receive(
        on connection: NWConnection,
        router: SessionAgentHTTPRouter,
        buffer: Data
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 1_048_576
        ) { data, _, _, error in
            if error != nil {
                connection.cancel()
                return
            }

            guard let data, data.isEmpty == false else {
                connection.cancel()
                return
            }

            var buffer = buffer
            buffer.append(data)
            guard HTTPWireCodec.isCompleteRequest(buffer) else {
                receive(on: connection, router: router, buffer: buffer)
                return
            }

            Task {
                let response: SessionAgentHTTPResponse
                do {
                    let request = try HTTPWireCodec.parseRequest(buffer)
                    response = await router.handle(request)
                } catch {
                    response = SessionAgentHTTPResponse(
                        statusCode: 400,
                        headers: ["Content-Type": "application/json"],
                        body: Data(#"{"error":{"code":"invalid_request","message":"Malformed HTTP request"}}"#.utf8)
                    )
                }

                connection.send(
                    content: HTTPWireCodec.serialize(response),
                    completion: .contentProcessed { _ in
                        connection.cancel()
                    }
                )
            }
        }
    }
}

public enum SessionAgentHTTPServerError: Error, LocalizedError, Equatable {
    case invalidPort(Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidPort(port):
            "invalid session agent port \(port)"
        }
    }
}

enum HTTPWireCodec {
    private static let headerSeparator = Data("\r\n\r\n".utf8)

    static func isCompleteRequest(_ data: Data) -> Bool {
        guard let separatorRange = data.range(of: headerSeparator) else {
            return false
        }

        let headerData = data[..<separatorRange.lowerBound]
        let headers = String(decoding: headerData, as: UTF8.self)
        let contentLength = headers
            .split(separator: "\r\n")
            .dropFirst()
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                    return nil
                }

                return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .first ?? 0

        let bodyStart = separatorRange.upperBound
        return data[bodyStart...].count >= contentLength
    }

    static func parseRequest(_ data: Data) throws -> SessionAgentHTTPRequest {
        guard let separator = data.range(of: headerSeparator) else {
            throw SessionAgentHTTPServerError.invalidPort(-1)
        }

        let headerBlock = String(decoding: data[..<separator.lowerBound], as: UTF8.self)
        let body = data[separator.upperBound...]
        let lines = headerBlock.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            throw SessionAgentHTTPServerError.invalidPort(-1)
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2,
              let method = SessionAgentHTTPRequest.Method(rawValue: String(parts[0])) else {
            throw SessionAgentHTTPServerError.invalidPort(-1)
        }

        return SessionAgentHTTPRequest(
            method: method,
            path: String(parts[1]),
            body: Data(body)
        )
    }

    static func serialize(_ response: SessionAgentHTTPResponse) -> Data {
        var headers = response.headers
        headers["Content-Length"] = "\(response.body.count)"
        headers["Connection"] = "close"

        let reason = reasonPhrase(for: response.statusCode)
        var data = Data("HTTP/1.1 \(response.statusCode) \(reason)\r\n".utf8)
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            data.append(Data("\(name): \(value)\r\n".utf8))
        }
        data.append(Data("\r\n".utf8))
        data.append(response.body)
        return data
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            "OK"
        case 400:
            "Bad Request"
        case 403:
            "Forbidden"
        case 404:
            "Not Found"
        case 501:
            "Not Implemented"
        default:
            "Internal Server Error"
        }
    }
}
