@testable import ComputerUseAgentCore
import Foundation
import Testing

@Test
func defaultSessionAgentRecordsUsageForActivationAndInspection() async throws {
    let textEdit = RunningApplication(
        bundleIdentifier: "com.apple.TextEdit",
        name: "TextEdit",
        processIdentifier: 838,
        isFrontmost: true
    )
    let preview = RunningApplication(
        bundleIdentifier: "com.apple.Preview",
        name: "Preview",
        processIdentifier: 839,
        isFrontmost: false
    )
    let usageTracker = RecordingApplicationUsageTracker()
    let stateCapturer = StubStateCapturer(applications: [preview, textEdit])
    let agent = DefaultComputerUseSessionAgent(
        permissionProvider: StaticPermissionService(),
        permissionRequester: StaticPermissionService(),
        applicationLister: StaticApplicationLister(applications: [textEdit, preview]),
        applicationActivator: StaticApplicationActivator(application: textEdit),
        applicationUsageTracker: usageTracker,
        stateCapturer: stateCapturer,
        actionPerformer: NoopActionPerformer()
    )

    let activatedApplication = try await agent.activateApplication(target: "TextEdit")
    #expect(activatedApplication.bundleIdentifier == "com.apple.TextEdit")
    #expect(activatedApplication.useCount == 1)

    let snapshot = try await agent.captureState(bundleIdentifier: "com.apple.TextEdit")
    #expect(snapshot.snapshotID == "snap-usage")
    #expect(stateCapturer.bundleIdentifiers == ["com.apple.TextEdit"])
    #expect(usageTracker.recordedApplications.map(\.bundleIdentifier) == [
        "com.apple.TextEdit",
        "com.apple.TextEdit",
    ])
}

@Test
func defaultSessionAgentMergesUsageIntoRunningApplications() async throws {
    let textEdit = RunningApplication(
        bundleIdentifier: "com.apple.TextEdit",
        name: "TextEdit",
        processIdentifier: 838,
        isFrontmost: true
    )
    let recentPreview = RunningApplication(
        bundleIdentifier: "com.apple.Preview",
        name: "Preview",
        processIdentifier: 0,
        isFrontmost: false,
        isRunning: false,
        lastUsed: Date(timeIntervalSince1970: 1_000),
        useCount: 4
    )
    let usageTracker = RecordingApplicationUsageTracker(mergedApplications: [textEdit, recentPreview])
    let applicationLister = StaticApplicationLister(applications: [textEdit])
    let agent = DefaultComputerUseSessionAgent(
        permissionProvider: StaticPermissionService(),
        permissionRequester: StaticPermissionService(),
        applicationLister: applicationLister,
        applicationActivator: StaticApplicationActivator(application: textEdit),
        applicationUsageTracker: usageTracker,
        stateCapturer: StubStateCapturer(applications: [textEdit]),
        actionPerformer: NoopActionPerformer()
    )

    #expect(try await agent.runningApplications() == [textEdit, recentPreview])
    #expect(usageTracker.mergeInputs == [[textEdit]])
}

private final class StaticPermissionService: PermissionStatusProviding, PermissionRequesting, @unchecked Sendable {
    func currentPermissions() async throws -> PermissionSnapshot {
        PermissionSnapshot(accessibility: .authorized, screenRecording: .authorized)
    }

    func requestPermissions() async throws -> PermissionSnapshot {
        try await currentPermissions()
    }
}

private final class StaticApplicationLister: RunningApplicationListing, @unchecked Sendable {
    private let applications: [RunningApplication]

    init(applications: [RunningApplication]) {
        self.applications = applications
    }

    func runningApplications() async throws -> [RunningApplication] {
        applications
    }
}

private final class StaticApplicationActivator: ApplicationActivating, @unchecked Sendable {
    private let application: RunningApplication

    init(application: RunningApplication) {
        self.application = application
    }

    func activateApplication(target: String) async throws -> RunningApplication {
        application
    }
}

private final class RecordingApplicationUsageTracker: ApplicationUsageTracking, @unchecked Sendable {
    private(set) var recordedApplications: [RunningApplication] = []
    private(set) var mergeInputs: [[RunningApplication]] = []
    private let mergedApplications: [RunningApplication]?

    init(mergedApplications: [RunningApplication]? = nil) {
        self.mergedApplications = mergedApplications
    }

    func recordUsage(application: RunningApplication) throws -> RunningApplication {
        recordedApplications.append(application)
        var updated = application
        updated.lastUsed = Date(timeIntervalSince1970: Double(recordedApplications.count))
        updated.useCount = recordedApplications.count
        return updated
    }

    func applicationsByMergingUsage(
        with runningApplications: [RunningApplication]
    ) throws -> [RunningApplication] {
        mergeInputs.append(runningApplications)
        return mergedApplications ?? runningApplications
    }
}

private final class StubStateCapturer: StateCapturing, @unchecked Sendable {
    private let applications: [RunningApplication]
    private(set) var bundleIdentifiers: [String?] = []

    init(applications: [RunningApplication]) {
        self.applications = applications
    }

    func captureState(bundleIdentifier: String?) async throws -> AgentStateSnapshot {
        bundleIdentifiers.append(bundleIdentifier)
        return AgentStateSnapshot(
            snapshotID: "snap-usage",
            screenshot: ScreenshotFrame(
                encoding: .png,
                size: Size(width: 1, height: 1),
                bytes: []
            ),
            accessibilityRoot: AccessibilityNode(id: "root", role: "AXApplication"),
            applications: applications
        )
    }
}

private struct NoopActionPerformer: ActionPerforming {
    func click(_ request: ClickActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func type(_ request: TypeActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func key(_ request: KeyActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func drag(_ request: DragActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func scroll(_ request: ScrollActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func setValue(_ request: SetValueActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }

    func perform(_ request: ElementActionRequest) async throws -> ActionReceipt {
        ActionReceipt(accepted: true)
    }
}
