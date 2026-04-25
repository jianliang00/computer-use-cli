@testable import ComputerUseAgentApp
import Foundation
import Testing

@Test
func httpWireCodecWaitsForFullContentLengthBody() {
    let partial = Data("""
    POST /actions/type HTTP/1.1\r
    Host: 127.0.0.1:7777\r
    Content-Type: application/json\r
    Content-Length: 16\r
    \r
    {\"text\":
    """.utf8)
    #expect(HTTPWireCodec.isCompleteRequest(partial) == false)

    let complete = Data("""
    POST /actions/type HTTP/1.1\r
    Host: 127.0.0.1:7777\r
    Content-Type: application/json\r
    Content-Length: 16\r
    \r
    {\"text\":\"hello\"}
    """.utf8)
    #expect(HTTPWireCodec.isCompleteRequest(complete))
}

@Test
func httpWireCodecParsesBodyAsRawData() throws {
    let payload = Data("""
    POST /actions/type HTTP/1.1\r
    Host: 127.0.0.1:7777\r
    Content-Type: application/json\r
    Content-Length: 16\r
    \r
    {\"text\":\"hello\"}
    """.utf8)

    let request = try HTTPWireCodec.parseRequest(payload)
    #expect(request.method == .post)
    #expect(request.path == "/actions/type")
    #expect(String(decoding: request.body, as: UTF8.self) == #"{"text":"hello"}"#)
}
