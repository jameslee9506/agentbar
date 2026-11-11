import AgentBarCore
import Foundation

final class FakeCodexProcesses: ProcessListing, @unchecked Sendable {
    private let lock = NSLock()
    private var owners: [Int32: (RunningProcess, [String])] = [:]
    private var polls = 0

    var pollCount: Int { lock.withLock { polls } }

    func own(_ files: [URL], pid: Int32 = 42, mode: String = "exec", start: Date = CodexFixture.date.addingTimeInterval(-100), executable: String = "/bin/codex") {
        lock.withLock {
            owners[pid] = (RunningProcess(pid: pid, parentPID: 1, executablePath: executable, arguments: [executable, mode], environment: [:], workingDirectory: nil, startTime: start), files.map(\.path))
        }
    }

    func remove(_ pid: Int32 = 42) { lock.withLock { _ = owners.removeValue(forKey: pid) } }

    func summaries() -> [ProcessSummary] {
        lock.withLock {
            polls += 1
            return owners.values.map { ProcessSummary(pid: $0.0.pid, parentPID: 1, name: URL(fileURLWithPath: $0.0.executablePath).lastPathComponent, startTime: $0.0.startTime) }
        }
    }

    func details(for pid: Int32) -> RunningProcess? { lock.withLock { owners[pid]?.0 } }
    func openFilePaths(of pid: Int32) -> [String] { lock.withLock { owners[pid]?.1 ?? [] } }
    func isAlive(_ pid: Int32, startedAt: Date?) -> Bool { lock.withLock { owners[pid].map { startedAt == nil || $0.0.startTime == startedAt } ?? false } }
}
