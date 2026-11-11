import AgentBarCore
@testable import CodexProvider
import CryptoKit
import Foundation
import Testing

struct CodexStatisticsCacheTests {
    @Test func oneCompactArchivePerHomeContainsAggregatesAndHashedIdentities() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let other = try fixture.home(".codex-other")
        let thread = "thread-identity-not-stored-as-text"
        let response = "response-identity-not-stored-as-text"
        _ = try fixture.rollout(home, name: "first", lines: [fixture.metadata(thread), fixture.context(), fixture.ledger(response, thread: thread)])
        _ = try fixture.rollout(other, name: "second", lines: [fixture.metadata(), fixture.context(), fixture.ledger("other")])
        let provider = fixture.provider()
        #expect(await provider.statistics(for: fixture.account(home), days: 7).total.total == 120)
        #expect(await provider.statistics(for: fixture.account(other), days: 7).total.total == 120)
        let files = try FileManager.default.contentsOfDirectory(at: fixture.cache, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        let cache = DiskCache(directory: fixture.cache)
        let data = try #require(cache.load(Data.self, key: CodexStatisticsArchive.key(home: home)))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains(thread))
        #expect(!text.contains(response))
        #expect(!text.contains("shared-session"))
        let archive = try #require(CodexStatisticsArchive.load(cache: cache, home: home, calendar: .current))
        #expect(archive.files.count == 1)
        #expect(archive.files.values.first?.responses.count == 1)
        #expect(archive.files.values.first?.ledger.count == 1)
        #expect(data.count < 2048)
    }

    @Test func deletedCopyTransfersAccountingAndDeletedEntriesDisappear() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let lines = [fixture.metadata(), fixture.context(), fixture.ledger("response")]
        let original = try fixture.rollout(home, name: "a-original", lines: lines)
        let copy = try fixture.rollout(home, name: "b-copy", lines: lines)
        let provider = fixture.provider()
        let account = fixture.account(home)
        #expect(await provider.statistics(for: account, days: 7).total.total == 120)
        try FileManager.default.removeItem(at: original)
        #expect(await provider.statistics(for: account, days: 7).total.total == 120)
        let cache = DiskCache(directory: fixture.cache)
        #expect(CodexStatisticsArchive.load(cache: cache, home: home, calendar: .current)?.files.count == 1)
        try FileManager.default.removeItem(at: copy)
        #expect(await provider.statistics(for: account, days: 7) == .empty)
        #expect(CodexStatisticsArchive.load(cache: cache, home: home, calendar: .current)?.files.isEmpty == true)
        #expect(await fixture.provider().statistics(for: account, days: 7) == .empty)
        #expect(try FileManager.default.contentsOfDirectory(at: fixture.cache, includingPropertiesForKeys: nil).count == 1)
    }

    @Test(arguments: [false, true])
    func corruptAndOldArchivesAreRebuilt(_ oldFormat: Bool) async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        _ = try fixture.rollout(home, lines: [fixture.metadata(), fixture.context(), fixture.ledger("response")])
        let cache = DiskCache(directory: fixture.cache)
        var data = Data("corrupt".utf8)
        if oldFormat {
            var writer = CodexStatisticsBinary.Writer()
            writer.string("codex.statistics.2")
            data = writer.data
            data.append(contentsOf: SHA256.hash(data: data))
        }
        try cache.save(data, key: CodexStatisticsArchive.key(home: home))
        #expect(await fixture.provider().statistics(for: fixture.account(home), days: 7).total.total == 120)
        #expect(CodexStatisticsArchive.load(cache: cache, home: home, calendar: .current)?.files.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(at: fixture.cache, includingPropertiesForKeys: nil).count == 1)
    }

    @Test func filesOutsideTheNewRangeArePrunedAndWiderRequestsRebuild() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let oldDate = CodexFixture.date.addingTimeInterval(-10 * 86400)
        let old = try fixture.rollout(home, name: "old", lines: [fixture.metadata("old-thread"), fixture.context(), fixture.ledger("old-response", thread: "old-thread", at: oldDate)])
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: old.path)
        _ = try fixture.rollout(home, name: "new", lines: [fixture.metadata(), fixture.context(), fixture.ledger("new-response")])
        let provider = fixture.provider()
        let account = fixture.account(home)
        #expect(await provider.statistics(for: account, days: 90).total.total == 240)
        #expect(await provider.statistics(for: account, days: 7).total.total == 120)
        #expect(CodexStatisticsArchive.load(cache: DiskCache(directory: fixture.cache), home: home, calendar: .current)?.files.count == 1)
        #expect(await provider.statistics(for: account, days: 90).total.total == 240)
    }

    @Test func copyAppendAndLateLedgerReplaceLegacyAcrossFiles() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let original = try fixture.rollout(home, name: "original", lines: [fixture.metadata(), fixture.context(), fixture.counter(input: 100)])
        let copy = try fixture.rollout(home, name: "copy", lines: [fixture.metadata(), fixture.context(), fixture.counter(input: 100)])
        let provider = fixture.provider()
        let account = fixture.account(home)
        #expect(await provider.statistics(for: account, days: 7).total.total == 100)
        try fixture.append([fixture.ledger("response", input: 50, cached: 0, output: 5)], to: copy)
        #expect(await provider.statistics(for: account, days: 7).total.total == 55)
        try fixture.append([fixture.ledger("response", input: 50, cached: 0, output: 5)], to: original)
        #expect(await fixture.provider().statistics(for: account, days: 7).total.total == 55)
    }

    @Test func calendarChangesRebuildDayBuckets() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        _ = try fixture.rollout(home, lines: [fixture.metadata(), fixture.context(), fixture.ledger("response")])
        var first = Calendar(identifier: .gregorian)
        first.timeZone = TimeZone(secondsFromGMT: 0)!
        var second = first
        second.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let account = fixture.account(home)
        let calendar = CalendarSource(first)
        let provider = CodexProvider(homeRoot: fixture.root, processes: FakeCodexProcesses(), transport: FakeCodexTransport(), clock: { CodexFixture.date }, cacheDirectory: fixture.cache, currentCalendar: { calendar.get() })
        let original = await provider.statistics(for: account, days: 7)
        #expect(original.total.total == 120)
        #expect(original.days.first?.day == first.startOfDay(for: CodexFixture.date))
        calendar.set(second)
        let result = await provider.statistics(for: account, days: 7)
        #expect(result.total.total == 120)
        #expect(result.days.first?.day == second.startOfDay(for: CodexFixture.date))
        let cache = DiskCache(directory: fixture.cache)
        #expect(CodexStatisticsArchive.load(cache: cache, home: home, calendar: first) == nil)
        #expect(CodexStatisticsArchive.load(cache: cache, home: home, calendar: second) != nil)
    }
}

private final class CalendarSource: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Calendar
    init(_ value: Calendar) { self.value = value }
    func get() -> Calendar { lock.withLock { value } }
    func set(_ value: Calendar) { lock.withLock { self.value = value } }
}
