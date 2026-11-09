import Foundation
import MurmurEngine
import Testing
import TranscriptCleanup

struct ClaudeCLICleanerTests {
    /// `prepare` spawns claude at key-down; a claude that rejects a flag (an older Claude Code without
    /// `--effort`) exits at once, so by key-up nothing reads its stdin.
    @Test func aClaudeThatExitedBeforeKeyUpFailsTheCleanupInsteadOfKillingTheApp() async {
        await #expect(processExitsWith: .success) {
            let session = ClaudeCLICleaner(model: "haiku", executable: URL(fileURLWithPath: "/usr/bin/false"))
                .prepare(instructions: "Clean this up.")
            try await Task.sleep(for: .seconds(1))
            _ = try? await session.clean(CleanupPrompt(transcript: "send it by friday please"))
        }
    }
}
