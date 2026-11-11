import AgentBarCore
import Foundation

enum TestFixtures {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    static func account(_ name: String, kind: ProviderKind = .claude) -> Account {
        Account(id: AccountID(provider: kind, home: "test-\(name)"), name: name,
                home: URL(fileURLWithPath: "/synthetic/\(kind.rawValue)/\(name)"), email: "\(name)@example.test", plan: "Test")
    }

    static func snapshot(_ percent: Double, at date: Date = date, reset: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(windows: [UsageWindow(id: "short", title: "5h", usedPercent: percent, resetsAt: reset)], capturedAt: date)
    }

    static func activity(_ state: AgentSession.State) -> AccountActivity {
        AccountActivity(sessions: [AgentSession(id: "test-session", state: state, directory: "/synthetic/project", since: date)])
    }
}
