@testable import AgentBar
import AgentBarCore
import Foundation
import Testing

@MainActor
struct StatusItemLoggerTests {
    @Test func logsOnlyPlanChangesWithWorkingCounts() {
        let a = descriptor(name: "personal", working: 2)
        let b = descriptor(name: "codex", kind: .codex)
        var lines: [String] = []
        let logger = StatusItemLogger { lines.append($0) }
        logger.record([a, b])
        logger.record([a, b])
        #expect(lines == ["items: claude:personal working=2 · codex"])
        let combined = StatusItemDescriptor(id: .overview, provider: nil, name: nil, workingCount: 3, accessibilityLabel: "AgentBar")
        logger.record([combined])
        #expect(lines.last == "items: combined working=3")
        #expect(lines.count == 2)
    }

    @Test func hiddenAndEmailNamesAreSafeAndCompact() {
        let unnamed = descriptor(name: nil)
        let email = descriptor(name: "private@example.test", working: 1)
        let newline = descriptor(name: "work\nproject")
        let line = StatusItemLogger.line(for: [unnamed, email, newline])
        #expect(line == "items: claude · claude working=1 · claude:work project")
        #expect(!line.contains("@"))
        #expect(!line.contains("private"))
        #expect(!line.contains("\n"))
        let long = descriptor(name: "a-long-account-label")
        #expect(StatusItemLogger.line(for: [long]) == "items: claude:a-long-account-…")
    }

    @Test func logArgumentWorksWithRealDemoAndSnapshotModes() throws {
        #expect(try LaunchOptions(arguments: ["AgentBar", "--log"]).log)
        #expect(try !LaunchOptions(arguments: ["AgentBar", "--log"]).demo)
        #expect(try LaunchOptions(arguments: ["AgentBar", "--demo", "--log"]).log)
        #expect(try LaunchOptions(arguments: ["AgentBar", "--snapshot", "/synthetic/snapshots", "--log"]).log)
        #expect(try !LaunchOptions(arguments: ["AgentBar", "--demo"]).log)
    }

    private func descriptor(name: String?, kind: ProviderKind = .claude, working: Int = 0) -> StatusItemDescriptor {
        StatusItemDescriptor(
            id: .account(TestFixtures.account("test", kind: kind).id), provider: kind, name: name,
            workingCount: working, accessibilityLabel: "Test account"
        )
    }
}
