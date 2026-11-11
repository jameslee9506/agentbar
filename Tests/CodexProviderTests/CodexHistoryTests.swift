import AgentBarCore
@testable import CodexProvider
import Foundation
import Testing

struct CodexHistoryTests {
    @Test func equivalentFilesystemPathsKeepHistoryKeysRelative() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata()])
        let enumerator = try #require(FileManager.default.enumerator(
            at: home.appendingPathComponent("sessions"), includingPropertiesForKeys: nil
        ))
        let enumerated = try #require(enumerator.allObjects.compactMap { $0 as? URL }
            .first { $0.pathExtension == "jsonl" })
        var paths = CodexHistoryPaths(home: home)
        let originalStamp = paths.stamp(file)
        let stamp = try #require(originalStamp)
        let enumeratedStamp = paths.stamp(enumerated)
        #expect(enumeratedStamp == stamp)
        #expect(CodexRolloutFile.inventory(home: home, since: .distantPast) == [
            "sessions/2026/11/10/thread.jsonl": stamp,
        ])
    }

    @Test func overlappingLegacyCopiesReconcileBeforeTakingDeltas() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let original = try fixture.rollout(home, name: "first", lines: [
            fixture.metadata(), fixture.context(), fixture.counter(input: 100), fixture.counter(input: 300),
        ])
        let copy = try fixture.rollout(home, name: "second", lines: [
            fixture.metadata(), fixture.context(), fixture.counter(input: 200), fixture.counter(input: 300),
        ])
        var paths = CodexHistoryPaths(home: home)
        #expect(paths.stamp(original) != nil)
        #expect(CodexRolloutFile.inventory(home: home, since: .distantPast).count == 2)
        let provider = fixture.provider()
        let account = fixture.account(home)
        #expect(await provider.statistics(for: account, days: 7).total.total == 300)
        try fixture.append([fixture.counter(input: 350)], to: copy)
        #expect(await provider.statistics(for: account, days: 7).total.total == 350)
        #expect(await fixture.provider().statistics(for: account, days: 7).total.total == 350)
        try FileManager.default.removeItem(at: original)
        #expect(await provider.statistics(for: account, days: 7).total.total == 350)
    }

    @Test(arguments: [false, true])
    func escapingHistoryLinksAreIgnoredByEveryReader(_ directoryLink: Bool) async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let other = try fixture.home(".codex-other")
        try fixture.auth(home)
        let file = try fixture.rollout(other, lines: [fixture.metadata(), fixture.context(), fixture.event("task_started"), fixture.ledger("response"), fixture.quota(45)])
        let sessions = home.appendingPathComponent("sessions")
        let link: URL
        if directoryLink {
            try FileManager.default.createSymbolicLink(at: sessions, withDestinationURL: other.appendingPathComponent("sessions"))
            link = sessions.appendingPathComponent("2026/11/10/thread.jsonl")
        } else {
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            link = sessions.appendingPathComponent("linked.jsonl")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        }
        let processes = FakeCodexProcesses()
        processes.own([link])
        let provider = fixture.provider(processes: processes)
        let account = fixture.account(home)
        #expect(await provider.statistics(for: account, days: 7) == .empty)
        #expect(await provider.cachedUsage(for: account) == nil)
        var monitor = CodexSessionMonitor(accounts: [account], processes: processes, rollouts: CodexRolloutUsage())
        #expect(monitor.poll()[account.id]?.sessions.isEmpty == true)
        #expect(await provider.statistics(for: fixture.account(other), days: 7).total.total == 120)
    }

    @Test func copiedLegacyReplayDoesNotMoveEarlierUsageToALaterDay() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let earlier = CodexFixture.date.addingTimeInterval(-86400)
        _ = try fixture.rollout(home, name: "first", lines: [
            fixture.metadata(), fixture.context(), fixture.counter(input: 100), fixture.counter(input: 300),
        ])
        _ = try fixture.rollout(home, name: "second", lines: [
            fixture.metadata(), fixture.context(), fixture.counter(input: 200, at: earlier), fixture.counter(input: 300),
        ])
        let result = await fixture.provider().statistics(for: fixture.account(home), days: 7)
        #expect(result.days.map { $0.total.total } == [200, 100])
        #expect(result.total.total == 300)
    }

    @Test func additionalQuotaKeepsTheLatestMainAndAdditionalBuckets() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home)
        func extra(_ percent: Int, at date: Date) -> String {
            fixture.row("event_msg", ["type": "token_count", "rate_limits": [
                "limit_id": "extra", "limit_name": "Extra model",
                "primary": ["used_percent": percent, "window_minutes": 60],
            ]], at: date)
        }
        _ = try fixture.rollout(home, lines: [
            fixture.metadata(), fixture.quota(20), extra(7, at: CodexFixture.date.addingTimeInterval(10)),
            fixture.quota(30, at: CodexFixture.date.addingTimeInterval(5)),
            extra(2, at: CodexFixture.date.addingTimeInterval(1)),
        ])
        let snapshot = try #require(await fixture.provider().cachedUsage(for: fixture.account(home)))
        #expect(snapshot.windows.map(\.id) == ["weekly", "additional.extra.window.3600"])
        #expect(snapshot.windows.map(\.usedPercent) == [30, 7])
        #expect(snapshot.capturedAt == CodexFixture.date.addingTimeInterval(5))
    }

    @Test func linksWithinHistoryRemainUsableAndReplacedEscapingLinksLoseCachedTotals() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let other = try fixture.home(".codex-other")
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.context(), fixture.ledger("response")])
        let external = try fixture.rollout(other, lines: [fixture.metadata(), fixture.context(), fixture.ledger("external", input: 300)])
        let link = file.deletingLastPathComponent().appendingPathComponent("copy.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let account = fixture.account(home)
        let provider = fixture.provider()
        #expect(await provider.statistics(for: account, days: 7).total.total == 120)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: external)
        #expect(await provider.statistics(for: account, days: 7) == .empty)
        #expect(await fixture.provider().statistics(for: account, days: 7) == .empty)
    }

    @Test func ownedRolloutsSupplyUsageOutsideRecentDateDirectories() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        try fixture.auth(home)
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.quota(50)])
        let older = home.appendingPathComponent("sessions/2000/01/01/owned.jsonl")
        try FileManager.default.createDirectory(at: older.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: file, to: older)
        for index in 0..<12 { _ = try fixture.rollout(home, name: "recent-\(index)", lines: [fixture.metadata("recent-\(index)")]) }
        let processes = FakeCodexProcesses()
        processes.own([older])
        #expect(await fixture.provider(processes: processes).cachedUsage(for: fixture.account(home))?.windows.first?.usedPercent == 50)
    }
}
