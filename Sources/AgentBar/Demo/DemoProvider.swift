import AgentBarCore
import Foundation

struct DemoProvider: AccountProvider {
    let kind: ProviderKind
    let date: Date
    let accountCount: Int

    init(kind: ProviderKind, date: Date = .now, accountCount: Int = 4) {
        self.kind = kind
        self.date = date
        self.accountCount = max(0, accountCount)
    }

    func accounts() async -> [Account] {
        let samples = switch kind {
        case .claude:
            [account("personal", plan: "Max"), account("research", plan: "Max"),
             account("studio", plan: "Pro"), account("writing", plan: "Pro")]
        case .codex:
            [account("codex", plan: "Plus"), account("review", plan: "Plus"),
             account("sandbox", plan: nil), account("workbench", plan: "Pro")]
        }
        return (0..<accountCount).map { index in
            index < samples.count ? samples[index] : account("account-\(index + 1)", plan: "Pro")
        }
    }

    func cachedUsage(for account: Account) async -> UsageSnapshot? {
        snapshot(for: account)
    }

    func usage(for account: Account) async throws(UsageError) -> UsageSnapshot {
        if account.name == "studio" { throw .sessionExpired }
        guard let snapshot = snapshot(for: account) else { throw .signedOut }
        return snapshot
    }

    func activity(for accounts: [Account]) -> AsyncStream<[AccountID: AccountActivity]> {
        let values = Dictionary(uniqueKeysWithValues: accounts.map { account in
            let sessions: [AgentSession] = account.name == "personal" ? [
                AgentSession(id: "demo-session-a", state: .working, directory: "/demo/projects/agentbar", since: date.addingTimeInterval(-480)),
                AgentSession(id: "demo-session-b", state: .working, directory: "/demo/projects/website", since: date.addingTimeInterval(-125)),
            ] : account.name == "workbench" ? [
                AgentSession(id: "demo-session-d", state: .working, directory: "/demo/projects/library", since: date.addingTimeInterval(-240)),
            ] : account.name == "codex" ? [
                AgentSession(id: "demo-session-c", state: .idle, directory: "/demo/projects/notes", since: date.addingTimeInterval(-1_200)),
            ] : []
            return (account.id, AccountActivity(sessions: sessions))
        })
        return AsyncStream { continuation in
            continuation.yield(values)
            continuation.finish()
        }
    }

    func statistics(for account: Account, days: Int) async -> UsageStatistics {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let multiplier = account.name == "personal" ? 4 : account.name == "studio" ? 2 : 1
        let models = kind == .claude ? ["Sonnet", "Opus"] : ["GPT-5", "GPT-5 Mini"]
        return UsageStatistics(days: (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let count = (8 + (offset * 7 + multiplier * 3) % 19) * 1_000 * multiplier
            return DailyUsage(day: day, byModel: [
                models[0]: TokenCount(input: count, output: count / 3, cacheRead: count * 2, cacheWrite: count / 5),
                models[1]: TokenCount(input: count / 3, output: count / 7, cacheRead: count / 2, cacheWrite: count / 9),
            ])
        })
    }

    private func account(_ name: String, plan: String?) -> Account {
        let home = "demo-\(kind.rawValue)-\(name)"
        return Account(
            id: AccountID(provider: kind, home: home), name: name,
            home: URL(fileURLWithPath: "/demo/\(home)"), email: "\(name)@example.test", plan: plan
        )
    }

    private func snapshot(for account: Account) -> UsageSnapshot? {
        switch account.name {
        case "personal":
            return UsageSnapshot(windows: [
                UsageWindow(id: "session", title: "5h", usedPercent: 43, resetsAt: date.addingTimeInterval(7_680)),
                UsageWindow(id: "weekly", title: "Week", usedPercent: 68, resetsAt: date.addingTimeInterval(259_200)),
            ], capturedAt: date)
        case "studio":
            return UsageSnapshot(windows: [
                UsageWindow(id: "session", title: "5h", usedPercent: 81, resetsAt: date.addingTimeInterval(-300)),
                UsageWindow(id: "weekly", title: "Week", usedPercent: 87, resetsAt: date.addingTimeInterval(93_600)),
            ], capturedAt: date.addingTimeInterval(-2_700))
        case "codex":
            return UsageSnapshot(windows: [
                UsageWindow(id: "session", title: "5h", usedPercent: 28, resetsAt: date.addingTimeInterval(10_800)),
            ], capturedAt: date)
        case "research", "writing", "review", "workbench":
            let percent = account.name == "research" ? 62.0 : account.name == "writing" ? 17.0 : account.name == "review" ? 39.0 : 72.0
            return UsageSnapshot(windows: [
                UsageWindow(id: "session", title: "5h", usedPercent: percent, resetsAt: date.addingTimeInterval(9_000)),
                UsageWindow(id: "weekly", title: "Week", usedPercent: min(100, percent + 12), resetsAt: date.addingTimeInterval(345_600)),
            ], capturedAt: date)
        default: return nil
        }
    }
}
