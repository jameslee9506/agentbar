import AgentBarCore
@testable import ClaudeProvider
import Foundation
import Darwin
import Testing

struct StatisticsTests {
    @Test func compactCachePrunesDeletedAndOutOfRangeFiles() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let recent = try transcript(account, path: "project/recent.jsonl")
        let older = try transcript(account, path: "project/older.jsonl")
        try row("recent", output: 10).write(to: recent)
        try row("older", output: 20, timestamp: "2026-11-08T00:00:00Z").write(to: older)
        try FileManager.default.setAttributes([.modificationDate: testNow.addingTimeInterval(-2 * 86_400)], ofItemAtPath: older.path)
        let cache = DiskCache(directory: space.cache)
        let scanner = HomeStatistics(home: account.home, cache: cache)
        #expect(await scan(scanner).total.output == 30)
        let key = TranscriptCache.key(home: account.home)
        let first = try #require(cache.load(TranscriptCache.self, key: key))
        #expect(first.checkpoints.count == 2)
        #expect(first.models == ["claude-opus"])
        #expect(TranscriptLedgerCoding.decode(first.ledger, files: 2, models: 1)?.count == 2)
        #expect(try FileManager.default.contentsOfDirectory(at: space.cache, includingPropertiesForKeys: nil).count == 1)
        let narrow = await scanner.scan(since: testNow, until: testNow.addingTimeInterval(86_400), calendar: calendar("UTC"))
        #expect(narrow.total.output == 10)
        #expect(cache.load(TranscriptCache.self, key: key)?.checkpoints.map(\.path) == ["project/recent.jsonl"])
        try FileManager.default.removeItem(at: recent)
        let restored = HomeStatistics(home: account.home, cache: cache)
        #expect(await restored.scan(since: testNow, until: testNow.addingTimeInterval(86_400), calendar: calendar("UTC")) == .empty)
        #expect(cache.load(TranscriptCache.self, key: key)?.checkpoints.isEmpty == true)
        #expect(try FileManager.default.contentsOfDirectory(at: space.cache, includingPropertiesForKeys: nil).count == 1)
    }

    @Test func corruptAndOldCacheFormatsAreRebuilt() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/main.jsonl")
        try row("one", output: 17).write(to: file)
        let cache = DiskCache(directory: space.cache)
        #expect(await scan(HomeStatistics(home: account.home, cache: cache)).total.output == 17)
        let key = TranscriptCache.key(home: account.home)
        let saved = try #require(cache.load(TranscriptCache.self, key: key))
        let old = TranscriptCache(version: TranscriptCache.currentVersion - 1, since: saved.since, calendar: saved.calendar,
            checkpoints: saved.checkpoints, models: saved.models, totals: .empty, ledger: saved.ledger)
        #expect(!old.isValid) // A valid checksum cannot make the previous request-identity format reusable.
        try cache.save(old, key: key)
        let fromOld = HomeStatistics(home: account.home, cache: cache)
        #expect(await scan(fromOld).total.output == 17)
        #expect(await fromOld.parsedFileCount == 1)
        var corrupt = saved.ledger
        corrupt[corrupt.count - 1] ^= 1
        try cache.save(TranscriptCache(version: TranscriptCache.currentVersion, since: saved.since, calendar: saved.calendar,
            checkpoints: saved.checkpoints, models: saved.models, totals: .empty, ledger: corrupt, checksum: saved.checksum), key: key)
        let fromCorrupt = HomeStatistics(home: account.home, cache: cache)
        #expect(await scan(fromCorrupt).total.output == 17)
        #expect(await fromCorrupt.parsedFileCount == 1)
        try cache.save(TranscriptCache(version: TranscriptCache.currentVersion, since: saved.since, calendar: saved.calendar,
            checkpoints: saved.checkpoints, models: saved.models, totals: .empty, ledger: saved.ledger, checksum: saved.checksum), key: key)
        #expect(await scan(HomeStatistics(home: account.home, cache: cache)).total.output == 17)
        let cacheFile = try #require(FileManager.default.contentsOfDirectory(at: space.cache, includingPropertiesForKeys: nil).first)
        try Data("truncated-json".utf8).write(to: cacheFile)
        #expect(await scan(HomeStatistics(home: account.home, cache: cache)).total.output == 17)
        #expect(cache.load(TranscriptCache.self, key: key)?.isValid == true)
    }

    @Test func restoredLedgerSupportsAppendAndLargeCounters() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/main.jsonl")
        try row("one", output: 10).write(to: file)
        let cache = DiskCache(directory: space.cache)
        #expect(await scan(HomeStatistics(home: account.home, cache: cache)).total.output == 10)
        try append(row("one", output: 30), to: file)
        let restored = HomeStatistics(home: account.home, cache: cache)
        #expect(await scan(restored).total.output == 30)
        let hash = TranscriptHash(low: 1, high: 2)
        let preciseTime = Date(timeIntervalSinceReferenceDate: 800_000_000.0.nextUp)
        let entry = TranscriptUsage(timestamp: preciseTime, tokens: TokenCount(input: Int.max, output: 0, cacheRead: 3, cacheWrite: 4),
                                    offset: 123, file: 0, model: 0, flags: 3)
        let encoded = TranscriptLedgerCoding.encode([hash: entry])
        #expect(TranscriptLedgerCoding.decode(encoded, files: 1, models: 1) == [hash: entry])
        #expect(TranscriptLedgerCoding.decode(Data(encoded.dropLast()), files: 1, models: 1) == nil)
        #expect(TranscriptLedgerCoding.decode(encoded, files: 0, models: 1) == nil)
    }

    @Test func largeTranscriptDoesNotRetainReadBuffers() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/large.jsonl")
        try row("one", output: 10).write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        let block = Data(("{\"type\":\"progress\",\"text\":\"" + String(repeating: "x", count: 256 * 1024) + "\"}\n").utf8)
        for _ in 0..<1_024 { try handle.write(contentsOf: block) }
        // One oversized line must also be skipped with bounded memory and an exact checkpoint.
        let oversized = Data(repeating: 120, count: 256 * 1024)
        for _ in 0..<128 { try handle.write(contentsOf: oversized) }
        try handle.write(contentsOf: Data([10]))
        try handle.write(contentsOf: row("two", output: 20))
        try handle.close()
        var before = rusage()
        getrusage(RUSAGE_SELF, &before)
        let scanner = HomeStatistics(home: account.home, cache: DiskCache(directory: space.cache))
        #expect(await scan(scanner).total.output == 30)
        var after = rusage()
        getrusage(RUSAGE_SELF, &after)
        #expect(after.ru_maxrss - before.ru_maxrss < 80 * 1024 * 1024)
        try append(row("three", output: 30), to: file)
        #expect(await scan(scanner).total.output == 60)
    }

    @Test func cacheRebuildDoesNotSweepOtherCacheFiles() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/main.jsonl")
        try row("one", output: 5).write(to: file)
        let cache = DiskCache(directory: space.cache)
        let old: [String: Any] = ["stamp": ["device": 1, "inode": 2, "size": 3, "modifiedSeconds": 4,
            "modifiedNanoseconds": 0, "changedSeconds": 4, "changedNanoseconds": 0], "offset": 3,
            "prefixHash": Data(repeating: 0, count: 32).base64EncodedString(),
            "boundaryHash": Data(repeating: 0, count: 32).base64EncodedString(), "rows": [:]]
        try space.write(old, to: space.cache.appendingPathComponent("old-orphan.json"))
        let unrelated = space.cache.appendingPathComponent("unrelated.json")
        try space.write(["version": 1, "other": "preserve"], to: unrelated)
        let calendar = calendar("UTC")
        let store = StatisticsStore(cache: cache, clock: { testNow }, calendar: { calendar })
        #expect(await store.statistics(for: account, days: 90).total.output == 5)
        #expect(FileManager.default.fileExists(atPath: space.cache.appendingPathComponent("old-orphan.json").path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(try FileManager.default.contentsOfDirectory(at: space.cache, includingPropertiesForKeys: nil).count == 3)
    }

    @Test func globalDedupPrefersCompleteMainRowsAndBucketsLocalDays() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/main.jsonl")
        let copy = try transcript(account, path: "project/session/subagents/workflows/workflow/agent-copy.jsonl")
        let first = try row("one", output: 8, complete: false, timestamp: "2026-11-10T23:59:00Z")
        let final = try row("one", output: 392, timestamp: "2026-11-11T00:01:00Z")
        let laterPartial = try row("one", output: 900, complete: false, timestamp: "2026-11-11T00:02:00Z")
        let earlierDay = try row("two", output: 10, model: "claude-sonnet", timestamp: "2026-11-10T07:00:00Z")
        let synthetic = try row("error", output: 999, model: "<synthetic>")
        try (first + final + laterPartial + earlierDay + synthetic + Data("invalid-json\n".utf8)).write(to: file)
        try (row("one", output: 777, sidechain: true, timestamp: "2026-11-11T01:00:00Z")
            + earlierDay + row("three", output: 20, sidechain: true)).write(to: copy)
        let scanner = HomeStatistics(home: account.home, cache: DiskCache(directory: space.cache))
        let result = await scan(scanner, calendar: calendar("America/Los_Angeles"))
        #expect(result.total == TokenCount(input: 9, output: 422, cacheRead: 15, cacheWrite: 21))
        #expect(result.days.count == 2)
        #expect(result.days.first?.day == Timestamps.parse("2026-11-09T08:00:00Z"))
        #expect(result.days.last?.day == Timestamps.parse("2026-11-10T08:00:00Z"))
        #expect(result.days.first?.byModel["claude-sonnet"]?.output == 10)
        #expect(result.days.last?.byModel["claude-opus"]?.output == 412)
        try FileManager.default.removeItem(at: file)
        let remaining = await scan(scanner, calendar: calendar("America/Los_Angeles"))
        #expect(remaining.total.output == 807) // The surviving copy becomes authoritative.
    }

    @Test func messageIdentityPrecedesSessionAndUUIDFallbacks() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/main.jsonl")
        let copy = try transcript(account, path: "project/copy.jsonl")
        let sessionOne = try row("same", output: 1, request: false, session: "session-one")
        let sessionTwo = try row("same", output: 2, request: false, session: "session-two")
        let uuid = try row("uuid-row", output: 3, request: false, session: nil, messageID: false)
        let anonymous = try row("no-id", output: 4, request: false, session: nil, messageID: false, uuid: false)
        try (sessionOne + sessionTwo + uuid + anonymous + anonymous).write(to: file)
        try (sessionOne + uuid).write(to: copy)
        let scanner = HomeStatistics(home: account.home, cache: DiskCache(directory: space.cache))
        #expect(await scan(scanner).total.output == 13)
    }

    @Test func missingOrDifferentRequestIDsStillIdentifyOneMessage() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/main.jsonl")
        let cache = DiskCache(directory: space.cache)
        try row("one", output: 10, request: false, session: nil).write(to: file)
        let scanner = HomeStatistics(home: account.home, cache: cache)
        #expect(await scan(scanner).total.output == 10)
        try append(row("one", output: 99, complete: false), to: file)
        #expect(await scan(scanner).total.output == 10)
        try append(row("one", output: 10), to: file)
        #expect(await scan(scanner).total.output == 10)
        var changedRequest = try #require(JSONSerialization.jsonObject(with: row("one", output: 20)) as? [String: Any])
        changedRequest["requestId"] = "another-synthetic-request"
        changedRequest["sessionId"] = "another-synthetic-session"
        try append(JSONSerialization.data(withJSONObject: changedRequest, options: [.sortedKeys]) + Data([10]), to: file)
        let restored = HomeStatistics(home: account.home, cache: cache)
        #expect(await scan(restored).total.output == 20)
        let copy = try transcript(account, path: "project/copy.jsonl")
        try (row("one", output: 200, sidechain: true, request: false, session: nil)
             + row("two", output: 7, request: false, session: nil)).write(to: copy)
        #expect(await scan(restored).total.output == 27)
        let saved = try #require(cache.load(TranscriptCache.self, key: TranscriptCache.key(home: account.home)))
        #expect(TranscriptLedgerCoding.decode(saved.ledger, files: 2, models: 1)?.count == 2)
    }

    @Test func historyLinksCannotImportAnotherHomesTokensOrReuseCachedTotals() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let other = try space.account(".claude-other")
        let file = try transcript(account, path: "project/own.jsonl")
        let foreign = try transcript(other, path: "project/foreign.jsonl")
        try row("own", output: 10).write(to: file)
        try row("foreign", output: 100).write(to: foreign)
        let root = account.home.appendingPathComponent("projects")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("foreign.jsonl"), withDestinationURL: foreign)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("shared"),
                                                  withDestinationURL: foreign.deletingLastPathComponent())
        let cache = DiskCache(directory: space.cache)
        let scanner = HomeStatistics(home: account.home, cache: cache)
        #expect(await scan(scanner).total.output == 10)
        try FileManager.default.moveItem(at: root, to: account.home.appendingPathComponent("projects-backup"))
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: other.home.appendingPathComponent("projects"))
        #expect(await scan(scanner) == .empty)
        #expect(await scan(HomeStatistics(home: account.home, cache: cache)) == .empty)
        #expect(cache.load(TranscriptCache.self, key: TranscriptCache.key(home: account.home))?.checkpoints.isEmpty == true)
        #expect(await scan(HomeStatistics(home: other.home, cache: cache)).total.output == 100)
    }

    @Test func sharedReaderLimitAndOversizedRowsPreservePhysicalOffsets() throws {
        let space = try TestSpace()
        let file = try transcript(space.account(), path: "project/offsets.jsonl")
        let first = Data("first\n".utf8)
        let oversized = Data(repeating: 120, count: 16 * 1024 * 1024 + 1) + Data([10])
        let second = Data("second\n".utf8)
        let complete = first + oversized + second
        try (complete + Data("partial".utf8)).write(to: file)
        var positions: [UInt64] = []
        let boundary = try TranscriptLines.scan(file, from: 0, upTo: UInt64(complete.count + 7)) { _, offset in
            positions.append(offset)
        }
        #expect(positions == [0, UInt64(first.count + oversized.count)])
        #expect(boundary == UInt64(complete.count))
        var limited: [String] = []
        let limit = try TranscriptLines.scan(file, from: 0, upTo: UInt64(complete.count - 1)) { bytes, _ in
            limited.append(String(decoding: bytes, as: UTF8.self))
        }
        #expect(limited == ["first"])
        #expect(limit == UInt64(first.count + oversized.count))
        try append(Data("\nlast\n".utf8), to: file)
        var resumed: [UInt64] = []
        let end = try #require(TranscriptFileStamp.read(file)).size
        #expect(try TranscriptLines.scan(file, from: boundary, upTo: end) { _, offset in resumed.append(offset) } == end)
        #expect(resumed == [boundary, boundary + 8])
    }

    @Test func appendPartialTailRewriteAndDiskRestore() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/main.jsonl")
        try row("one", output: 10).write(to: file)
        let cache = DiskCache(directory: space.cache)
        let scanner = HomeStatistics(home: account.home, cache: cache)
        #expect(await scan(scanner).total.output == 10)
        #expect(await scanner.parsedFileCount == 1)
        #expect(await scan(scanner).total.output == 10)
        #expect(await scanner.parsedFileCount == 1)
        try append(row("one", output: 20), to: file)
        #expect(await scan(scanner).total.output == 20)
        let next = try row("two", output: 30)
        let split = next.count / 2
        try append(next.prefix(split), to: file)
        #expect(await scan(scanner).total.output == 20)
        try append(next.suffix(next.count - split), to: file)
        #expect(await scan(scanner).total.output == 50)
        let restored = HomeStatistics(home: account.home, cache: cache)
        #expect(await scan(restored).total.output == 50)
        #expect(await restored.parsedFileCount == 0)
        try row("one", output: 90).write(to: file)
        #expect(await scan(scanner).total.output == 90)
        try row("one", output: 80).write(to: file) // Same length, changed contents.
        #expect(await scan(scanner).total.output == 80)
        try row("replacement", output: 7).write(to: file, options: .atomic)
        #expect(await scan(scanner).total.output == 7)
        try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("moved.jsonl"))
        #expect(await scan(scanner).total.output == 7)
    }

    @Test func rewriteWithGrowthIsDetectedByFingerprints() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/main.jsonl")
        try row("old", output: 1).write(to: file)
        let scanner = HomeStatistics(home: account.home, cache: DiskCache(directory: space.cache))
        #expect(await scan(scanner).total.output == 1)
        try (row("new", output: 2) + row("extra", output: 3)).write(to: file)
        #expect(await scan(scanner).total.output == 5)
    }

    @Test func widerRangesLoadOlderFilesAndTimezoneChangesRebucket() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/older.jsonl")
        try row("old", output: 17, timestamp: "2026-11-08T23:30:00Z").write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Timestamps.parse("2026-11-09T00:00:00Z")!], ofItemAtPath: file.path)
        let scanner = HomeStatistics(home: account.home, cache: DiskCache(directory: space.cache))
        let utc = calendar("UTC")
        let narrow = await scanner.scan(since: testNow, until: testNow.addingTimeInterval(86_400), calendar: utc)
        #expect(narrow.days.isEmpty)
        #expect(await scanner.parsedFileCount == 0)
        let broad = await scan(scanner)
        #expect(broad.total.output == 17)
        #expect(broad.days.first?.day == Timestamps.parse("2026-11-08T00:00:00Z"))
        let korean = await scan(scanner, calendar: calendar("Asia/Seoul"))
        #expect(korean.days.first?.day == Timestamps.parse("2026-11-08T15:00:00Z"))
        #expect(await scanner.parsedFileCount == 1)
    }

    @Test func localCalendarHandlesDaylightSavingTransition() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/dst.jsonl")
        try (row("first-hour", output: 5, timestamp: "2026-11-01T08:30:00Z")
             + row("repeated-hour", output: 6, timestamp: "2026-11-01T09:30:00Z")).write(to: file)
        let scanner = HomeStatistics(home: account.home, cache: DiskCache(directory: space.cache))
        let result = await scanner.scan(since: Timestamps.parse("2026-10-31T00:00:00Z")!, until: testNow,
                                        calendar: calendar("America/Los_Angeles"))
        #expect(result.days.count == 1)
        #expect(result.days.first?.day == Timestamps.parse("2026-11-01T07:00:00Z"))
        #expect(result.total.output == 11)
    }

    @Test func concurrentHomeRequestsShareScanAndWarmRefreshIsFast() async throws {
        let space = try TestSpace()
        let account = try space.account()
        let file = try transcript(account, path: "project/main.jsonl")
        var data = Data()
        for index in 0..<3_000 { data.append(try row("request-\(index)", output: 2)) }
        try data.write(to: file)
        let calendar = calendar("UTC")
        let store = StatisticsStore(cache: DiskCache(directory: space.cache), clock: { testNow }, calendar: { calendar })
        let results = await withTaskGroup(of: UsageStatistics.self) { group in
            for _ in 0..<12 { group.addTask { await store.statistics(for: account, days: 7) } }
            var results: [UsageStatistics] = []
            for await result in group { results.append(result) }
            return results
        }
        #expect(results.count == 12)
        #expect(results.allSatisfy { $0.total.output == 6_000 })
        #expect(await store.scansStarted == 1)
        let clock = ContinuousClock()
        let started = clock.now
        let refresh = await store.statistics(for: account, days: 7)
        #expect(started.duration(to: clock.now) < .seconds(1))
        #expect(refresh.total.output == 6_000)
        #expect(await store.statistics(for: account, days: 0) == .empty)
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func scan(_ scanner: HomeStatistics, calendar: Calendar? = nil) async -> UsageStatistics {
        await scanner.scan(since: testNow.addingTimeInterval(-7 * 86_400), until: testNow.addingTimeInterval(86_400),
                           calendar: calendar ?? self.calendar("UTC"))
    }

    private func transcript(_ account: Account, path: String) throws -> URL {
        let file = account.home.appendingPathComponent("projects/" + path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return file
    }

    private func append(_ data: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func row(_ id: String, output: Int, model: String = "claude-opus", complete: Bool = true,
                     sidechain: Bool = false, timestamp: String = "2026-11-11T00:01:00Z", request: Bool = true,
                     session: String? = "synthetic-session", messageID: Bool = true, uuid: Bool = true) throws -> Data {
        var message: [String: Any] = ["model": model, "role": "assistant", "content": [["type": "text", "text": "Synthetic text"]],
            "stop_reason": complete ? "tool_use" : NSNull(),
            "usage": ["input_tokens": 3, "output_tokens": output, "cache_read_input_tokens": 5, "cache_creation_input_tokens": 7,
                      "cache_creation": ["ephemeral_5m_input_tokens": 7], "output_tokens_details": ["thinking_tokens": 1],
                      "iterations": [["output_tokens": output]]]]
        if messageID { message["id"] = "message-" + id }
        var object: [String: Any] = ["type": "assistant", "timestamp": timestamp, "isSidechain": sidechain, "message": message]
        if request { object["requestId"] = "request-" + id }
        if uuid { object["uuid"] = "row-" + id }
        object["sessionId"] = session
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(10)
        return data
    }
}
