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
