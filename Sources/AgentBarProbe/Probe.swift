import AgentBarCore
import ClaudeProvider
import CodexProvider
import Foundation

/// Prints what the providers see on this machine, without any UI.
///
/// `--days` defaults to 90, the range the app loads, so a probe run reuses the app's statistics cache.
///
/// Usage: `agentbar-probe [claude] [codex] [--days N] [--offline] [--repeat] [--watch]`
@main
struct Probe {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let named = arguments.compactMap(ProviderKind.init(rawValue:))
        let all: [any AccountProvider] = [ClaudeProvider(), CodexProvider()]
        let providers = all.filter { named.isEmpty || named.contains($0.kind) }

        let days = arguments.firstIndex(of: "--days").flatMap { Int(arguments[safe: $0 + 1] ?? "") } ?? 90
        for provider in providers {
            await report(
                provider,
                days: days,
                live: !arguments.contains("--offline"),
                repeats: arguments.contains("--repeat")
            )
        }
        if arguments.contains("--watch") {
            await watch(providers)
        }
    }

    private static func report(_ provider: any AccountProvider, days: Int, live: Bool, repeats: Bool) async {
        let accounts = await provider.accounts()
        emit("== \(provider.kind.displayName): \(accounts.count) account(s)")
        let activity = await firstActivity(of: provider, accounts: accounts)

        for account in accounts {
            emit("\(account.name)  \(masked(account.email))  \(account.plan ?? "-")  \(account.home.path)")

            let cached = await provider.cachedUsage(for: account)
            emit("  cached    \(cached.map(describe) ?? "none")")
            if live {
                do {
                    emit("  live      \(describe(try await provider.usage(for: account)))")
                } catch {
                    emit("  live      \(error)")
                }
            }

            let sessions = activity[account.id]?.sessions ?? []
            emit("  sessions  \(sessions.count { $0.state == .working }) working, \(sessions.count) open")
            for session in sessions {
                let directory = session.directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "-"
                emit("    \(session.state.rawValue)  \(directory)  \(session.since.map(age) ?? "")")
            }

            let started = Date()
            let statistics = await provider.statistics(for: account, days: days)
            var elapsed = Date().timeIntervalSince(started).formatted(.number.precision(.fractionLength(2)))
            if repeats {
                let restarted = Date()
                _ = await provider.statistics(for: account, days: days)
                elapsed += "s, repeat " + Date().timeIntervalSince(restarted).formatted(.number.precision(.fractionLength(3)))
            }
            let today = statistics.days.last.flatMap { Calendar.current.isDateInToday($0.day) ? $0.total.total : nil }
            let models = Set(statistics.days.flatMap(\.byModel.keys)).sorted().joined(separator: ", ")
            emit("  tokens    today \(today ?? 0) · \(days)d \(statistics.total.total) · \(statistics.days.count) day(s) · \(models) · \(elapsed)s")
        }
    }

    private static func firstActivity(
        of provider: any AccountProvider,
        accounts: [Account]
    ) async -> [AccountID: AccountActivity] {
        let stream = provider.activity(for: accounts)
        return await withTaskGroup(of: [AccountID: AccountActivity]?.self) { group in
            group.addTask {
                for await state in stream { return state }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? [:]
        }
    }

    private static func watch(_ providers: [any AccountProvider]) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    let accounts = await provider.accounts()
                    let names = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
                    for await state in provider.activity(for: accounts) {
                        let summary = state.sorted { $0.key < $1.key }
                            .map { "\(names[$0.key] ?? $0.key.home)=\($0.value.workingCount)/\($0.value.sessions.count)" }
                            .joined(separator: " ")
                        emit("\(Date().formatted(date: .omitted, time: .standard))  \(provider.kind.rawValue)  \(summary)")
                    }
                }
            }
        }
    }

    private static func describe(_ snapshot: UsageSnapshot) -> String {
        let windows = snapshot.windows.map { window in
            let reset = window.resetsAt.map { ", resets in \(duration($0.timeIntervalSinceNow))" } ?? ""
            return "\(window.title) \(Int(window.usedPercent.rounded()))%\(reset)"
        }
        return "\(windows.joined(separator: " · "))  (\(age(snapshot.capturedAt)) ago)"
    }

    private static func age(_ date: Date) -> String {
        duration(Date().timeIntervalSince(date))
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes >= 1440 { return "\(minutes / 1440)d \(minutes % 1440 / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    private static func masked(_ email: String?) -> String {
        guard let email, let at = email.firstIndex(of: "@"), let first = email.first else { return "-" }
        return "\(first)***\(email[at...])"
    }

    /// Unbuffered output, so `--watch` stays live when piped.
    private static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
