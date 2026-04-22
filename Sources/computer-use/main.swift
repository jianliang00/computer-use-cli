import ComputerUseCLI
import Foundation

@main
enum ComputerUseMain {
    static func main() {
        let tool = CommandLineTool()

        do {
            let output = try tool.run(arguments: Array(CommandLine.arguments.dropFirst()))
            guard output.isEmpty == false else {
                return
            }

            FileHandle.standardOutput.write(Data((output + "\n").utf8))
        } catch {
            let message = error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
            FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
