import AgentBarCore
import Foundation

struct CodexSessionMonitor {
    private let accounts: [Account]
    private let processes: any ProcessListing
    private let rollouts: CodexRolloutUsage
    private let bootstrapBudget: Duration
    private var threads: [String: CodexOwnedThread] = [:]

    static func stream(
        accounts: [Account], processes: any ProcessListing, rollouts: CodexRolloutUsage, interval: Duration
    ) -> AsyncStream<[AccountID: AccountActivity]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached(priority: .utility) {
                var monitor = Self(accounts: accounts, processes: processes, rollouts: rollouts)
                var previous: [AccountID: AccountActivity]?
                while !Task.isCancelled {
                    let current = monitor.poll()
                    if current != previous {
                        continuation.yield(current)
                        previous = current
                    }
                    do { try await Task.sleep(for: monitor.threads.values.contains(where: \.isSearching) ? min(interval, .milliseconds(50)) : interval) }
                    catch { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    init(accounts: [Account], processes: any ProcessListing, rollouts: CodexRolloutUsage, bootstrapBudget: Duration = .milliseconds(20)) {
        self.accounts = accounts
        self.processes = processes
        self.rollouts = rollouts
        self.bootstrapBudget = bootstrapBudget
    }

    mutating func poll() -> [AccountID: AccountActivity] {
        let homes = accounts.map { ($0, $0.home.resolvingSymlinksInPath().standardizedFileURL.path + "/") }
        var owned: [String: (Account, Date)] = [:]
        for summary in processes.summaries() where summary.name == "codex" {
            guard let process = processes.details(for: summary.pid), process.startTime == summary.startTime,
                  URL(fileURLWithPath: process.executablePath).lastPathComponent == "codex"
            else { continue }
            let paths = processes.openFilePaths(of: process.pid)
            guard processes.isAlive(process.pid, startedAt: process.startTime) else { continue }
            for path in paths where path.hasSuffix(".jsonl") {
                let normalized = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
                guard let (account, prefix) = homes.first(where: { normalized.hasPrefix($0.1) }),
                      normalized.hasPrefix(prefix + "sessions/") || normalized.hasPrefix(prefix + "archived_sessions/")
                else { continue }
                let start = min(owned[normalized]?.1 ?? process.startTime, process.startTime)
                owned[normalized] = (account, start)
            }
        }
        threads = threads.filter { owned[$0.key] != nil }
        var result = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, AccountActivity.none) })
        for account in accounts {
            var historyPaths = CodexHistoryPaths(home: account.home)
            let paths = owned.filter { $0.value.0.id == account.id }.keys.sorted()
            for path in paths {
                let file = URL(fileURLWithPath: path)
                guard let stamp = historyPaths.stamp(file) else { threads.removeValue(forKey: path); continue }
                if var thread = threads[path], thread.canAppend(file: file, stamp: stamp) {
                    thread.update(file: file, stamp: stamp, home: account.home, rollouts: rollouts)
                    threads[path] = thread
                } else {
                    threads[path] = CodexOwnedThread(file: file, home: account.home, rollouts: rollouts)
                }
            }
            let deadline = ContinuousClock.now.advanced(by: bootstrapBudget)
            while ContinuousClock.now < deadline {
                let searching = paths.filter { threads[$0]?.isSearching == true }
                if searching.isEmpty { break }
                for path in searching {
                    guard ContinuousClock.now < deadline, var thread = threads[path] else { break }
                    thread.update(file: URL(fileURLWithPath: path), stamp: thread.stamp, home: account.home, rollouts: rollouts)
                    threads[path] = thread
                }
            }
            var groups: [String: [AgentSession]] = [:]
            var directories: [String: String] = [:]
            for path in paths {
                guard let thread = threads[path], let owner = owned[path] else { continue }
                let metadata = thread.metadata
                let root = metadata.sessionID.flatMap { $0.isEmpty ? nil : $0 } ?? metadata.parentID ?? metadata.id
                let active = thread.turns.running.values.filter { $0 >= owner.1.addingTimeInterval(-1) }
                let session = AgentSession(
                    id: thread.metadata.id, state: active.isEmpty ? .idle : .working,
                    directory: metadata.directory, since: active.min() ?? thread.turns.endedAt
                )
                groups[root, default: []].append(session)
                if directories[root] == nil || metadata.parentID == nil { directories[root] = metadata.directory }
            }
            let sessions = groups.map { id, children in
                let working = children.filter { $0.state == .working }
                return AgentSession(
                    id: id, state: working.isEmpty ? .idle : .working, directory: directories[id],
                    since: working.isEmpty ? children.compactMap(\.since).max() : working.compactMap(\.since).min()
                )
            }.sorted {
                if $0.state != $1.state { return $0.state == .working }
                if $0.since != $1.since { return ($0.since ?? .distantPast) > ($1.since ?? .distantPast) }
                return $0.id < $1.id
            }
            result[account.id] = AccountActivity(sessions: sessions)
        }
        return result
    }
}
