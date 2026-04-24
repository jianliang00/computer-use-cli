import BootstrapAgent
import Foundation

@main
enum BootstrapAgentMain {
    static func main() async {
        let configuration = BootstrapAgentConfiguration.guestDefault
        let service = DefaultBootstrapStatusService(configuration: configuration)

        do {
            let status = try await service.refreshStatus()
            try appendLog("refreshed status: bootstrapped=\(status.bootstrapped)", configuration: configuration)
        } catch {
            let message = error.localizedDescription.isEmpty
                ? String(describing: error)
                : error.localizedDescription
            try? appendLog("error: \(message)", configuration: configuration)
            FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func appendLog(
        _ message: String,
        configuration: BootstrapAgentConfiguration
    ) throws {
        let url = URL(fileURLWithPath: configuration.logFilePath)
        let directory = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: directory.path) == false {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let line = "[\(Date())] \(message)\n"
        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url, options: .atomic)
        }
    }
}
