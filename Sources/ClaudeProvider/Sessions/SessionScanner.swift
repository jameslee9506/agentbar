import AgentBarCore
import Foundation

struct SessionScanner {
    private struct ProcessState {
        let summary: ProcessSummary
        let home: String?
        let directory: String?
    }

    let root: URL
    let processes: any ProcessListing
    private var knownProcesses: [Int32: ProcessState] = [:]

    init(root: URL, processes: any ProcessListing) {
        self.root = root
        self.processes = processes
    }

    mutating func snapshot(accounts: [Account], refreshProcesses: Bool = true) -> [AccountID: AccountActivity] {
        if refreshProcesses { refresh() }
        var result = Dictionary(accounts.map { ($0.id, AccountActivity.none) }, uniquingKeysWith: { first, _ in first })
        var attributed = Set<Int32>()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        for account in accounts.sorted(by: { $0.id < $1.id }) {
            let home = account.home.standardizedFileURL.path
            let history = HistoryDirectory(home: account.home, component: "sessions")
            let files = history.flatMap { try? FileManager.default.contentsOfDirectory(
                at: $0.root, includingPropertiesForKeys: nil
            ) } ?? []
            var sessions: [AgentSession] = []
            for file in files {
                guard let history, let registry = SessionRegistration.read(file, within: history),
                      let process = knownProcesses[registry.pid],
                      process.home == nil || process.home == home,
                      let registeredStart = formatter.date(from: registry.procStart),
                      floor(process.summary.startTime.timeIntervalSince1970) == registeredStart.timeIntervalSince1970,
                      processes.isAlive(registry.pid, startedAt: process.summary.startTime),
                      attributed.insert(registry.pid).inserted
                else { continue }
                sessions.append(AgentSession(
                    id: sessionID(process.summary, account: account),
                    state: registry.status == "busy" ? .working : .idle,
                    directory: registry.cwd,
                    since: registry.statusUpdatedAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
                ))
            }
            for process in knownProcesses.values where process.home == home && !attributed.contains(process.summary.pid) {
                guard processes.isAlive(process.summary.pid, startedAt: process.summary.startTime) else { continue }
                attributed.insert(process.summary.pid)
                sessions.append(AgentSession(id: sessionID(process.summary, account: account), state: .idle,
                                             directory: process.directory))
            }
            sessions.sort {
                if $0.state != $1.state { return $0.state == .working }
                if $0.since != $1.since { return ($0.since ?? .distantPast) > ($1.since ?? .distantPast) }
                return $0.id < $1.id
            }
            result[account.id] = AccountActivity(sessions: sessions)
        }
        return result
    }

    private mutating func refresh() {
        var refreshed: [Int32: ProcessState] = [:]
        for summary in processes.summaries() where summary.name == "claude" || Self.isVersion(summary.name) {
            if let existing = knownProcesses[summary.pid], existing.summary.startTime == summary.startTime {
                refreshed[summary.pid] = existing
                continue
            }
            let details = processes.details(for: summary.pid)
            guard details == nil || details?.startTime == summary.startTime else { continue }
            if let details, !Self.isClaudeInvocation(details) { continue }
            if summary.name != "claude" {
                guard let details, Self.isNativeClaude(details.executablePath) else { continue }
            }
            var home: String?
            if let details {
                if let configured = details.environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
                    let expanded = configured == "~" ? root.path
                        : (configured.hasPrefix("~/") ? root.appendingPathComponent(String(configured.dropFirst(2))).path : configured)
                    if expanded.hasPrefix("/") { home = URL(fileURLWithPath: expanded).standardizedFileURL.path }
                    else if let cwd = details.workingDirectory {
                        home = URL(fileURLWithPath: cwd).appendingPathComponent(expanded).standardizedFileURL.path
                    }
                } else if !details.environment.isEmpty {
                    home = root.appendingPathComponent(".claude").standardizedFileURL.path
                }
            }
            refreshed[summary.pid] = ProcessState(summary: summary, home: home, directory: details?.workingDirectory)
        }
        knownProcesses = refreshed
    }

    private func sessionID(_ process: ProcessSummary, account: Account) -> String {
        "\(account.id):\(process.pid):\(process.startTime.timeIntervalSince1970)"
    }

    private static func isVersion(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    private static func isNativeClaude(_ path: String) -> Bool {
        let executable = URL(fileURLWithPath: path)
        let versions = executable.deletingLastPathComponent()
        return isVersion(executable.lastPathComponent) && versions.lastPathComponent == "versions"
            && versions.deletingLastPathComponent().lastPathComponent == "claude"
    }

    private static func isClaudeInvocation(_ process: RunningProcess) -> Bool {
        guard let argument = process.arguments.first else { return false }
        let command = URL(fileURLWithPath: argument).lastPathComponent
        let native = isNativeClaude(process.executablePath)
            && command == URL(fileURLWithPath: process.executablePath).lastPathComponent
        guard command == "claude" || native else { return false }
        return !process.arguments.dropFirst().starts(with: ["mcp", "serve"])
    }
}
