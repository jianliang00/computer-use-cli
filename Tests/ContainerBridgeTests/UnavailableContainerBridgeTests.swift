import ContainerBridge
import Foundation
import Testing

@Test
func unavailableBridgeThrowsForInspect() throws {
    let bridge = UnavailableContainerBridge()

    do {
        _ = try bridge.inspectSandbox(id: "sandbox-123")
        Issue.record("expected unavailable bridge to throw")
    } catch let error as ContainerBridgeError {
        #expect(error == .notImplemented("inspectSandbox"))
    }
}
