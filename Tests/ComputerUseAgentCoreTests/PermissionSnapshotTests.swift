import XCTest
@testable import ComputerUseAgentCore

final class PermissionSnapshotTests: XCTestCase {
    func testMissingPermissionsReflectAutomationReadiness() {
        let snapshot = PermissionSnapshot(
            accessibility: .authorized,
            screenRecording: .denied
        )

        XCTAssertFalse(snapshot.isReadyForAutomation)
        XCTAssertEqual(snapshot.missingPermissions, [.screenRecording])
    }
}
