import ComputerUseAgentApp
import ComputerUseAgentCore
import Dispatch
import Foundation

@main
enum ComputerUseAgentMain {
    static func main() {
        let configuration = SessionAgentConfiguration.guestDefault
        let agent = DefaultComputerUseSessionAgent()
        let router = SessionAgentHTTPRouter(
            configuration: configuration,
            agent: agent
        )
        let server = SessionAgentHTTPServer(
            configuration: configuration,
            router: router
        )

        do {
            try server.start()
            dispatchMain()
        } catch {
            let message = error.localizedDescription.isEmpty
                ? String(describing: error)
                : error.localizedDescription
            FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
