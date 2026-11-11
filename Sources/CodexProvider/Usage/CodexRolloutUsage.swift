import AgentBarCore
import Foundation

final class CodexRolloutUsage: @unchecked Sendable {
    private let lock = NSLock()
    private var observations: [String: [String: Observation]] = [:]

    func observe(_ record: CodexRecord, metadata: CodexThreadMetadata, home: URL) {
        guard metadata.owns(record), record.type == "event_msg", record.event == "token_count",
              let object = record.payload["rate_limits"] as? [String: Any], let timestamp = record.timestamp
        else { return }
        let snapshot = CodexUsageDecoder.rollout(object, at: timestamp)
        guard !snapshot.windows.isEmpty else { return }
        let limit = object["limit_id"] as? String ?? "codex"
        let observation = Observation(limit: limit, snapshot: snapshot, account: metadata.creatorAccountDigest, user: metadata.creatorUserDigest)
        let bucket = limit + "." + (metadata.creatorAccountDigest ?? "unknown") + "." + (metadata.creatorUserDigest ?? "unknown")
        let key = home.standardizedFileURL.path
        lock.withLock {
            if observations[key]?[bucket].map({ $0.snapshot.capturedAt >= timestamp }) == true { return }
            observations[key, default: [:]][bucket] = observation
        }
    }

    func latest(home: URL, credential: CodexCredential) -> UsageSnapshot? {
        let values = lock.withLock { Array(observations[home.standardizedFileURL.path, default: [:]].values) }
            .filter { observation in
                if let account = observation.account, account != credential.accountDigest { return false }
                if let user = observation.user, let current = credential.userDigest, user != current { return false }
                return observation.account != nil || observation.snapshot.capturedAt >= credential.fileModifiedAt
            }
        var latest: [String: UsageSnapshot] = [:]
        for value in values {
            if latest[value.limit].map({ $0.capturedAt >= value.snapshot.capturedAt }) != true { latest[value.limit] = value.snapshot }
        }
        guard let capturedAt = latest.values.map(\.capturedAt).min() else { return nil }
        let limits = latest.keys.sorted { left, right in
            if left == "codex" || right == "codex" { return left == "codex" && right != "codex" }
            return left < right
        }
        return UsageSnapshot(windows: limits.flatMap { latest[$0]!.windows }, capturedAt: capturedAt)
    }

    func inspectRecent(home: URL, processes: any ProcessListing) {
        var files = Set(CodexRolloutFile.recentFiles(home: home))
        for summary in processes.summaries() where summary.name == "codex" {
            guard let process = processes.details(for: summary.pid), process.startTime == summary.startTime,
                  URL(fileURLWithPath: process.executablePath).lastPathComponent == "codex" else { continue }
            let paths = processes.openFilePaths(of: process.pid)
            guard processes.isAlive(process.pid, startedAt: process.startTime) else { continue }
            files.formUnion(paths.filter { $0.hasSuffix(".jsonl") }.map { URL(fileURLWithPath: $0) })
        }
        var paths = CodexHistoryPaths(home: home)
        for file in files where paths.stamp(file) != nil {
            guard let metadata = CodexRolloutFile.metadata(file),
                  let lines = try? JSONLines.tailLines(in: file, count: 512, maximumBytes: 256 * 1024)
            else { continue }
            for line in lines {
                line.withUnsafeBytes { bytes in
                    if let record = CodexRecord.decode(bytes) { observe(record, metadata: metadata, home: home) }
                }
            }
        }
    }

    private struct Observation {
        let limit: String
        let snapshot: UsageSnapshot
        let account: String?
        let user: String?
    }
}
