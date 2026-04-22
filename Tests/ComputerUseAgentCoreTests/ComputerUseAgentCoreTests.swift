import ComputerUseAgentApp
import ComputerUseAgentCore
import Testing

@Test
func sessionAgentDefaultsMatchTechnicalPlan() {
    let configuration = SessionAgentConfiguration.guestDefault

    #expect(configuration.bundleIdentifier == "io.github.jianliang00.computer-use.agent")
    #expect(configuration.bundlePath == "/Applications/ComputerUseAgent.app")
    #expect(configuration.launchAgentLabel == "io.github.jianliang00.computer-use.agent")
    #expect(configuration.host == "127.0.0.1")
    #expect(configuration.port == 7777)
    #expect(configuration.logFilePath == "/Users/admin/Library/Logs/ComputerUseAgent.log")
}

@Test
func snapshotCachePolicyDefaultsMatchTodoPlan() {
    let policy = SnapshotCachePolicy()

    #expect(policy.capacity == 8)
    #expect(policy.timeToLive == 60)
}
