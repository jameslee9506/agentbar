import AgentBarCore
import Foundation

actor CodexHomeStatistics {
    private let home: URL
    private let cache: DiskCache
    private let clock: @Sendable () -> Date
    private let rollouts: CodexRolloutUsage
    private let changes: CodexFileChanges
    private var state: CodexStatisticsArchive
    private var loaded = false
    private var reconciledAt: Date = .distantPast
    private var totals: [CodexStatisticsBucket: TokenCount] = [:]
    private var result: UsageStatistics = .empty
    private var resultRange: DateInterval?

    init(home: URL, cache: DiskCache, calendar: Calendar, clock: @escaping @Sendable () -> Date, rollouts: CodexRolloutUsage) {
        self.home = home
        self.cache = cache
        self.clock = clock
        self.rollouts = rollouts
        changes = CodexFileChanges(home: home)
        state = CodexStatisticsArchive(since: .distantFuture, calendarKey: CodexStatisticsArchive.calendarKey(calendar))
    }

    func statistics(days: Int, calendar: Calendar) -> UsageStatistics {
        autoreleasepool { scan(days: days, calendar: calendar) }
    }

    private func scan(days: Int, calendar: Calendar) -> UsageStatistics {
        guard days > 0 else { return .empty }
        let now = clock()
        let today = calendar.startOfDay(for: now)
        guard let since = calendar.date(byAdding: .day, value: 1 - days, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return .empty }
        let range = DateInterval(start: since, end: end)
        if state.calendarKey != CodexStatisticsArchive.calendarKey(calendar) {
            state = CodexStatisticsArchive(since: .distantFuture, calendarKey: CodexStatisticsArchive.calendarKey(calendar))
            loaded = false
            totals.removeAll(keepingCapacity: true)
            resultRange = nil
        }
        var changed = false
        var reconcile = !loaded
        if !loaded {
            loaded = true
            if let restored = CodexStatisticsArchive.load(cache: cache, home: home, calendar: calendar) {
                state = restored
                for checkpoint in state.files.values { totals.add(checkpoint.totals) }
            } else {
                changed = true
            }
        }
        if since < state.since {
            state = CodexStatisticsArchive(since: since, calendarKey: CodexStatisticsArchive.calendarKey(calendar))
            totals.removeAll(keepingCapacity: true)
            reconcile = true
            changed = true
        }
        let dirty = changes.take()
        reconcile = reconcile || now.timeIntervalSince(reconciledAt) >= 30 || dirty.contains { !$0.hasSuffix(".jsonl") }
        var paths = Set(state.files.keys)
        var inventory: [String: CodexFileStamp]?
        if reconcile {
            inventory = CodexRolloutFile.inventory(home: home, since: since)
            paths = Set(inventory!.keys)
            reconciledAt = now
        }
        for path in dirty where path.hasSuffix(".jsonl") {
            if let relative = relativePath(URL(fileURLWithPath: path)) { paths.insert(relative) }
        }
        var rebuild: Set<CodexStatisticsID> = []
        var read: Set<String> = []
        if since > state.since {
            for path in Array(state.files.keys) {
                guard var checkpoint = state.files.removeValue(forKey: path) else { continue }
                totals.add(checkpoint.totals, sign: -1)
                checkpoint.prune(before: Int64(since.timeIntervalSince1970))
                totals.add(checkpoint.totals)
                state.files[path] = checkpoint
            }
            state.since = since
            changed = true
        }
        for path in state.files.keys where !paths.contains(path) {
            if let previous = state.files.removeValue(forKey: path) {
                totals.add(previous.totals, sign: -1)
                rebuild.insert(previous.thread)
                changed = true
            }
        }
        var historyPaths = CodexHistoryPaths(home: home)
        let prefix = home.path + "/"
        for path in paths.sorted() {
            autoreleasepool {
                let absolute = prefix + path
                guard let stamp = inventory?[path] ?? historyPaths.stamp(path: absolute), stamp.modifiedAt >= since else {
                    if let previous = state.files.removeValue(forKey: path) {
                        totals.add(previous.totals, sign: -1)
                        rebuild.insert(previous.thread)
                        changed = true
                    }
                    return
                }
                if let previous = state.files[path] {
                    if previous.stamp == stamp { return }
                    let file = URL(fileURLWithPath: absolute)
                    if previous.canAppend(file: file, stamp: stamp) { read.insert(path); return }
                    totals.add(previous.totals, sign: -1)
                    rebuild.insert(previous.thread)
                }
                var checkpoint = CodexStatisticsCheckpoint(stamp: stamp)
                if let metadata = CodexRolloutFile.metadata(URL(fileURLWithPath: absolute)) { checkpoint.identify(metadata) }
                state.files[path] = checkpoint
                rebuild.insert(checkpoint.thread)
                read.insert(path)
                changed = true
            }
        }
        let affected = rebuild.union(read.compactMap { state.files[$0]?.thread })
        let groups = Dictionary(grouping: state.files.keys.filter { affected.contains(state.files[$0]!.thread) }, by: { state.files[$0]!.thread })
        for (thread, members) in groups {
            let members = members.sorted()
            guard rebuild.contains(thread) || members.contains(where: read.contains) else { continue }
            changed = true
            if members.count > 1 && thread != .zero {
                let files = members.compactMap { path -> (String, CodexFileStamp)? in
                    guard let previous = state.files.removeValue(forKey: path) else { return nil }
                    totals.add(previous.totals, sign: -1)
                    return (path, CodexFileStamp(home.appendingPathComponent(path)) ?? previous.stamp)
                }
                let replacements = CodexStatisticsCopies.rebuild(files: files, home: home, since: since, calendar: calendar, names: &state.models, rollouts: rollouts)
                for (path, checkpoint) in replacements {
                    state.files[path] = checkpoint
                    totals.add(checkpoint.totals)
                }
            } else {
                for path in members {
                    autoreleasepool {
                        guard var checkpoint = state.files.removeValue(forKey: path) else { return }
                        totals.add(checkpoint.totals, sign: -1)
                        if rebuild.contains(thread) { checkpoint = CodexStatisticsCheckpoint(stamp: checkpoint.stamp) }
                        checkpoint.read(file: home.appendingPathComponent(path), home: home, since: since, calendar: calendar, names: &state.models, rollouts: rollouts)
                        totals.add(checkpoint.totals)
                        state.files[path] = checkpoint
                    }
                }
            }
        }
        if changed { state.save(cache: cache, home: home) }
        if !changed, resultRange == range { return result }
        var days: [Int64: [String: TokenCount]] = [:]
        let lower = Int64(since.timeIntervalSince1970), upper = Int64(end.timeIntervalSince1970)
        for (bucket, tokens) in totals where bucket.day >= lower && bucket.day < upper {
            days[bucket.day, default: [:]][state.models.names[Int(bucket.model)], default: .zero] += tokens
        }
        result = UsageStatistics(days: days.map { DailyUsage(day: Date(timeIntervalSince1970: Double($0.key)), byModel: $0.value) }.sorted { $0.day < $1.day })
        resultRange = range
        return result
    }

    private func relativePath(_ file: URL) -> String? {
        let prefix = home.standardizedFileURL.path + "/"
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }
}
