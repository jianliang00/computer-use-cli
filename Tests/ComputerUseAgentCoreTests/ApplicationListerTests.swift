@testable import ComputerUseAgentCore
import Foundation
import Testing

@Test
func processTableApplicationListerAddsAppBundleProcessesMissingFromWorkspace() throws {
    let fileManager = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    let appURL = root.appendingPathComponent("TextEdit.app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
    try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)

    let infoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleExecutable</key>
      <string>TextEdit</string>
      <key>CFBundleIdentifier</key>
      <string>com.apple.TextEdit</string>
      <key>CFBundleName</key>
      <string>TextEdit</string>
    </dict>
    </plist>
    """
    try Data(infoPlist.utf8).write(to: contentsURL.appendingPathComponent("Info.plist"))

    let executableURL = macOSURL.appendingPathComponent("TextEdit")
    try Data().write(to: executableURL)

    let lister = ProcessTableApplicationLister(processProvider: {
        [
            ProcessTableApplication(
                processIdentifier: 838,
                executablePath: executableURL.path
            ),
        ]
    })

    let applications = lister.mergeApplications([], frontmostProcessIdentifier: 838)

    #expect(applications == [
        RunningApplication(
            bundleIdentifier: "com.apple.TextEdit",
            name: "TextEdit",
            processIdentifier: 838,
            isFrontmost: true
        ),
    ])
}

@Test
func applicationResolverMatchesBundleIDAndNameAndRejectsAmbiguity() throws {
    let resolver = ApplicationResolver()
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

    #expect(try resolver.resolve(target: "com.apple.TextEdit", applications: [textEdit, preview]) == textEdit)
    #expect(try resolver.resolve(target: "preview", applications: [textEdit, preview]) == preview)
    #expect(try resolver.resolve(target: "Safari", applications: [textEdit, preview]) == nil)

    do {
        _ = try resolver.resolve(target: "TextEdit", applications: [
            textEdit,
            RunningApplication(
                bundleIdentifier: "com.example.TextEdit",
                name: "TextEdit",
                processIdentifier: 840,
                isFrontmost: false
            ),
        ])
        Issue.record("expected ambiguous app target")
    } catch let error as ApplicationActivationError {
        guard case let .appAmbiguous(target, candidates) = error else {
            Issue.record("expected appAmbiguous, got \(error)")
            return
        }

        #expect(target == "TextEdit")
        #expect(candidates.map(\.bundleIdentifier) == ["com.apple.TextEdit", "com.example.TextEdit"])
    }
}

@Test
func fileApplicationUsageStoreRecordsAndMergesRecentApps() throws {
    let fileManager = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    let usageURL = root.appendingPathComponent("usage.json")
    let clock = TestClock(date: Date(timeIntervalSince1970: 4_000))
    let store = FileApplicationUsageStore(
        url: usageURL,
        now: { clock.date },
        retention: 14 * 24 * 60 * 60
    )
    let textEdit = RunningApplication(
        bundleIdentifier: "com.apple.TextEdit",
        name: "TextEdit",
        processIdentifier: 838,
        isFrontmost: true
    )

    let firstRecord = try store.recordUsage(application: textEdit)
    #expect(firstRecord.lastUsed == Date(timeIntervalSince1970: 4_000))
    #expect(firstRecord.useCount == 1)

    clock.date = Date(timeIntervalSince1970: 4_100)
    let secondRecord = try store.recordUsage(application: textEdit)
    #expect(secondRecord.useCount == 2)

    let mergedRunningApps = try store.applicationsByMergingUsage(with: [textEdit])
    #expect(mergedRunningApps[0].isRunning)
    #expect(mergedRunningApps[0].useCount == 2)

    let mergedRecentApps = try store.applicationsByMergingUsage(with: [])
    #expect(mergedRecentApps == [
        RunningApplication(
            bundleIdentifier: "com.apple.TextEdit",
            name: "TextEdit",
            processIdentifier: 0,
            isFrontmost: false,
            isRunning: false,
            lastUsed: Date(timeIntervalSince1970: 4_100),
            useCount: 2
        ),
    ])
}

@Test
func fileApplicationUsageStoreDropsApplicationsOutsideRetentionWindow() throws {
    let fileManager = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    let usageURL = root.appendingPathComponent("usage.json")
    let clock = TestClock(date: Date(timeIntervalSince1970: 1_000))
    let store = FileApplicationUsageStore(
        url: usageURL,
        now: { clock.date },
        retention: 60
    )

    _ = try store.recordUsage(application: RunningApplication(
        bundleIdentifier: "com.apple.TextEdit",
        name: "TextEdit",
        processIdentifier: 838,
        isFrontmost: true
    ))

    clock.date = Date(timeIntervalSince1970: 1_100)
    _ = try store.recordUsage(application: RunningApplication(
        bundleIdentifier: "com.apple.Preview",
        name: "Preview",
        processIdentifier: 839,
        isFrontmost: true
    ))

    #expect(try store.applicationsByMergingUsage(with: []) == [
        RunningApplication(
            bundleIdentifier: "com.apple.Preview",
            name: "Preview",
            processIdentifier: 0,
            isFrontmost: false,
            isRunning: false,
            lastUsed: Date(timeIntervalSince1970: 1_100),
            useCount: 1
        ),
    ])
}

private final class TestClock: @unchecked Sendable {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}
