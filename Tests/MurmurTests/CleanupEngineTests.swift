import Testing
import MurmurEngine

struct CleanupEngineTests {
    @Test func fallsBackFromClaudeToOnDeviceToOff() {
        #expect(CleanupEngine.claude.resolved(claudeInstalled: true, onDeviceAvailable: true, online: true) == .claude)
        #expect(CleanupEngine.claude.resolved(claudeInstalled: true, onDeviceAvailable: true, online: false) == .onDevice)
        #expect(CleanupEngine.claude.resolved(claudeInstalled: false, onDeviceAvailable: true, online: true) == .onDevice)
        #expect(CleanupEngine.claude.resolved(claudeInstalled: false, onDeviceAvailable: false, online: true) == .off)
        #expect(CleanupEngine.onDevice.resolved(claudeInstalled: true, onDeviceAvailable: false, online: true) == .off)
    }
}
