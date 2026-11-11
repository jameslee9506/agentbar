import AgentBarCore
import Foundation

actor HomeStatistics {
    private struct File {
        let path: String
        let stamp: TranscriptFileStamp
    }

    private let home: URL
    private let cache: DiskCache
    private var checkpoints: [TranscriptCheckpoint] = []
    private var rows: [TranscriptHash: TranscriptUsage]?
    private var packedRows: Data?
    private var models: [String] = []
    private var modelIDs: [String: UInt32] = [:]
    private var totals: [Date: [String: TokenCount]] = [:]
    private var dayIntervals: [Int64: [DateInterval]] = [:]
    private var lastCalendar: Calendar?
    private var since: Date?
    private var restored = false
    private(set) var scanCount = 0
    private(set) var parsedFileCount = 0

    init(home: URL, cache: DiskCache) {
        self.home = home
        self.cache = cache
    }

    func scan(since start: Date, until end: Date, calendar: Calendar) -> UsageStatistics {
        autoreleasepool { refresh(since: start, until: end, calendar: calendar) }
    }

    private func refresh(since start: Date, until end: Date, calendar: Calendar) -> UsageStatistics {
        scanCount += 1
        if !restored {
            restore()
            restored = true
        }
        let files = inventory(since: start)
        var rebuild = since != start || checkpoints.count != files.count
        var changed: [Int] = []
        if !rebuild {
            for (index, file) in files.enumerated() {
                let previous = checkpoints[index]
                if previous.path != file.path { rebuild = true; break }
                if previous.stamp == file.stamp { continue }
                guard let url = location(file.path), previous.canAppend(file: url, stamp: file.stamp)
                else { rebuild = true; break }
                changed.append(index)
            }
        }
        let rebucket = lastCalendar != calendar
        if !rebuild, (!changed.isEmpty || rebucket), !unpack() { rebuild = true }
        if rebuild {
            reset(since: start, calendar: calendar)
            changed = Array(files.indices)
        } else if rebucket {
            totals = [:]
            dayIntervals = [:]
            if let rows {
                for row in rows.values { contribute(row, sign: 1, calendar: calendar) }
            }
            lastCalendar = calendar
        }
        let parser = TranscriptParser()
        var failedPaths = Set<String>()
        for index in changed {
            let previous = rebuild ? nil : checkpoints[index]
            let checkpoint = autoreleasepool {
                read(files[index], index: index, previous: previous, parser: parser, calendar: calendar, updatingTotals: !rebuild)
            }
            guard let checkpoint else { failedPaths.insert(files[index].path); break }
            if rebuild { checkpoints.append(checkpoint) }
            else { checkpoints[index] = checkpoint }
        }
        if !failedPaths.isEmpty {
            // A rewrite or read failure during scanning invalidates the partial ledger, too.
            var retry = true
            while retry {
                retry = false
                reset(since: start, calendar: calendar)
                for file in files where !failedPaths.contains(file.path) {
                    let checkpoint = autoreleasepool {
                        read(file, index: checkpoints.count, previous: nil, parser: parser, calendar: calendar, updatingTotals: false)
                    }
                    guard let checkpoint else {
                        failedPaths.insert(file.path)
                        retry = true
                        break
                    }
                    checkpoints.append(checkpoint)
                }
            }
        }
        if rebuild || !failedPaths.isEmpty {
            totals = [:]
            if let rows {
                for row in rows.values { contribute(row, sign: 1, calendar: calendar) }
            }
        }
        if rebuild || rebucket || !changed.isEmpty || !failedPaths.isEmpty { persist() }
        return snapshot(since: start, until: end)
    }

    private func inventory(since start: Date) -> [File] {
        guard let history = HistoryDirectory(home: home, component: "projects") else { return [] }
        let root = history.root
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles])
        var files: [File] = []
        var identities = Set<TranscriptFileStamp.Identity>()
        var parents: [String: (allowed: Bool, relativePath: String)] = [:]
        while let file = enumerator?.nextObject() as? URL {
            autoreleasepool {
                guard file.pathExtension == "jsonl", let stamp = TranscriptFileStamp.read(file),
                      stamp.modifiedAt >= start else { return }
                // lstat excludes a symlink at the leaf; each parent is resolved once per inventory.
                let parent = file.deletingLastPathComponent()
                let directory: (allowed: Bool, relativePath: String)
                if let known = parents[parent.path] { directory = known }
                else {
                    let resolved = parent.resolvingSymlinksInPath()
                    directory = (history.contains(resolved), String(resolved.path.dropFirst(root.path.count)))
                    parents[parent.path] = directory
                }
                guard directory.allowed, identities.insert(stamp.identity).inserted else { return }
                let path = String((directory.relativePath + "/" + file.lastPathComponent).dropFirst())
                files.append(File(path: path, stamp: stamp))
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func read(_ file: File, index: Int, previous: TranscriptCheckpoint?, parser: TranscriptParser,
                      calendar: Calendar, updatingTotals: Bool) -> TranscriptCheckpoint? {
        guard let url = location(file.path) else { return nil }
        let offset = previous?.offset ?? 0
        do {
            parsedFileCount += 1
            let completeOffset = try TranscriptLines.scan(url, from: offset, upTo: file.stamp.size) { bytes, position in
                guard let (key, model, parsed) = parser.parse(bytes, fileIdentity: file.stamp.identity,
                                                              file: UInt32(index), offset: position) else { return }
                var row = parsed
                if let modelID = modelIDs[model] { row.model = modelID }
                else {
                    row.model = UInt32(models.count)
                    modelIDs[model] = row.model
                    models.append(model)
                }
                let old = rows?[key]
                guard old.map({ row.isPreferred(to: $0) }) ?? true else { return }
                rows?[key] = row
                if updatingTotals {
                    if let old { contribute(old, sign: -1, calendar: calendar) }
                    contribute(row, sign: 1, calendar: calendar)
                }
            }
            guard let finalStamp = TranscriptFileStamp.read(url), finalStamp.identity == file.stamp.identity,
                  finalStamp.size >= completeOffset,
                  let guards = TranscriptCheckpoint.fingerprints(file: url, offset: completeOffset)
            else { return nil }
            return TranscriptCheckpoint(path: file.path, stamp: file.stamp, offset: completeOffset,
                                        prefixHash: guards.0, boundaryHash: guards.1)
        } catch { return nil }
    }

    private func contribute(_ row: TranscriptUsage, sign: Int, calendar: Calendar) {
        let day = day(containing: row.timestamp, calendar: calendar)
        let model = models[Int(row.model)]
        var count = totals[day]?[model] ?? .zero
        count.input += sign * row.tokens.input
        count.output += sign * row.tokens.output
        count.cacheRead += sign * row.tokens.cacheRead
        count.cacheWrite += sign * row.tokens.cacheWrite
        totals[day, default: [:]][model] = count
    }

    private func day(containing date: Date, calendar: Calendar) -> Date {
        let bucket = Int64(floor(date.timeIntervalSince1970 / 86_400))
        if let cached = dayIntervals[bucket]?.first(where: { $0.start <= date && date < $0.end }) { return cached.start }
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return calendar.startOfDay(for: date) }
        dayIntervals[bucket, default: []].append(interval)
        return interval.start
    }

    private func snapshot(since start: Date = .distantPast, until end: Date = .distantFuture) -> UsageStatistics {
        UsageStatistics(days: totals.keys.sorted().filter { $0 >= start && $0 < end }.compactMap { day in
            guard let models = totals[day]?.filter({ $0.value != .zero }), !models.isEmpty else { return nil }
            return DailyUsage(day: day, byModel: models)
        })
    }

    private func reset(since start: Date, calendar: Calendar) {
        rows = [:]
        packedRows = nil
        checkpoints = []
        models = []
        modelIDs = [:]
        totals = [:]
        dayIntervals = [:]
        since = start
        lastCalendar = calendar
    }

    private func restore() {
        guard let saved = cache.load(TranscriptCache.self, key: TranscriptCache.key(home: home)), saved.isValid else { return }
        since = saved.since
        lastCalendar = saved.calendar
        checkpoints = saved.checkpoints
        models = saved.models
        modelIDs = Dictionary(uniqueKeysWithValues: models.enumerated().map { ($0.element, UInt32($0.offset)) })
        totals = Dictionary(saved.totals.days.map { ($0.day, $0.byModel) }, uniquingKeysWith: { _, last in last })
        packedRows = saved.ledger
    }

    private func unpack() -> Bool {
        if rows != nil { return true }
        guard let packedRows,
              let decoded = TranscriptLedgerCoding.decode(packedRows, files: checkpoints.count, models: models.count)
        else { return false }
        rows = decoded
        self.packedRows = nil
        return true
    }

    private func persist() {
        guard let since, let lastCalendar else { return }
        autoreleasepool {
            let data = rows.map(TranscriptLedgerCoding.encode) ?? packedRows ?? Data()
            let saved = TranscriptCache(version: TranscriptCache.currentVersion, since: since, calendar: lastCalendar,
                checkpoints: checkpoints, models: models, totals: snapshot(), ledger: data)
            try? cache.save(saved, key: TranscriptCache.key(home: home))
        }
    }

    private func location(_ path: String) -> URL? {
        guard let history = HistoryDirectory(home: home, component: "projects") else { return nil }
        return history.resolve(history.root.appendingPathComponent(path))
    }
}
