import AgentBarCore
@testable import CodexProvider
import Foundation
import Testing

struct CodexStatisticsTests {
    @Test func ledgerDeduplicatesCopiesAndUsesTurnModels() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let lines = [
            fixture.metadata(), fixture.context("one", model: "model-one"),
            fixture.ledger("response-one", turn: "one", written: 5),
            fixture.ledger("response-one", turn: "one", written: 5),
            fixture.context("two", model: "model-two"),
            fixture.ledger("response-two", turn: "two", input: 50, cached: 10, output: 5),
            fixture.ledger("foreign", thread: "another-thread", input: 9999),
            fixture.ledger("foreign-session", session: "wrong-session"),
        ]
        _ = try fixture.rollout(home, name: "original", lines: lines)
        _ = try fixture.rollout(home, name: "copy", lines: lines)
        let statistics = await fixture.provider().statistics(for: fixture.account(home), days: 7)
        #expect(statistics.total == TokenCount(input: 100, output: 25, cacheRead: 50, cacheWrite: 5))
        #expect(statistics.days.first?.byModel["model-one"] == TokenCount(input: 60, output: 20, cacheRead: 40, cacheWrite: 5))
        #expect(statistics.days.first?.byModel["model-two"] == TokenCount(input: 40, output: 5, cacheRead: 10))
    }

    @Test func ledgerReplacesLegacyOnlyForItsTurn() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        _ = try fixture.rollout(home, lines: [
            fixture.metadata(), fixture.context("ledger-turn"),
            fixture.counter(input: 100, cached: 40, output: 20),
            fixture.ledger("response", turn: "ledger-turn", cumulative: fixture.usage(input: 100, cached: 40, output: 20)),
            fixture.counter(input: 100, cached: 40, output: 20),
            fixture.context("legacy-turn", model: "legacy-model"),
            fixture.counter(input: 150, cached: 50, output: 30),
        ])
        let statistics = await fixture.provider().statistics(for: fixture.account(home), days: 7)
        #expect(statistics.total == TokenCount(input: 100, output: 30, cacheRead: 50))
        #expect(statistics.days.first?.byModel["legacy-model"] == TokenCount(input: 40, output: 10, cacheRead: 10))
    }

    @Test func legacyHighWaterSurvivesRepeatedSnapshotsCompactionAndReplay() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let lines = [
            fixture.metadata(), fixture.context(nil, model: "legacy-model"),
            fixture.counter(input: 100, cached: 20, output: 10),
            fixture.counter(input: 100, cached: 20, output: 10),
            fixture.row("compacted", ["replacement_history": [["type": "token_usage_record", "payload": ["usage": fixture.usage(input: 99999)]]]]),
            fixture.counter(input: 100, cached: 20, output: 10, last: ["input_tokens": 0, "output_tokens": 0, "total_tokens": 14017]),
            fixture.counter(input: 200, cached: 50, output: 20),
            fixture.counter(input: 150, cached: 30, output: 15),
            fixture.counter(input: 250, cached: 60, output: 25),
        ]
        _ = try fixture.rollout(home, name: "original", lines: lines)
        _ = try fixture.rollout(home, name: "copy", lines: lines)
        let statistics = await fixture.provider().statistics(for: fixture.account(home), days: 7)
        #expect(statistics.total == TokenCount(input: 190, output: 25, cacheRead: 60))
    }

    @Test func forkBoundaryKeepsLeafIdentityAndExcludesCopiedHistory() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        _ = try fixture.rollout(home, name: "child", lines: [
            fixture.metadata("child", parent: "parent", boundary: 10), fixture.metadata("parent"),
            fixture.context("parent-turn", model: "parent-model", ordinal: 2),
            fixture.ledger("parent-response", thread: "parent", turn: "parent-turn", ordinal: 3),
            fixture.counter(input: 1000, output: 100, ordinal: 4),
            fixture.context("child-turn", model: "child-model", ordinal: 10),
            fixture.ledger("child-response", thread: "child", turn: "child-turn", input: 30, cached: 10, output: 5, ordinal: 11),
        ])
        let statistics = await fixture.provider().statistics(for: fixture.account(home), days: 7)
        #expect(statistics.total == TokenCount(input: 20, output: 5, cacheRead: 10))
        #expect(statistics.days.first?.byModel.keys.sorted() == ["child-model"])
    }

    @Test func legacyForkBaselineIsConservative() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        _ = try fixture.rollout(home, name: "child", lines: [
            fixture.metadata("child", parent: "parent", boundary: 10),
            fixture.counter(input: 1000, cached: 400, output: 100, ordinal: 3),
            fixture.context("child-turn", ordinal: 10),
            fixture.counter(input: 1030, cached: 410, output: 105, last: fixture.usage(input: 30, cached: 10, output: 5), ordinal: 11),
        ])
        _ = try fixture.rollout(home, name: "ambiguous", lines: [fixture.metadata("ambiguous", parent: "missing"), fixture.context(), fixture.counter(input: 90000)])
        _ = try fixture.rollout(home, name: "independent", lines: [
            fixture.metadata("independent", parent: "parent", boundary: 10), fixture.counter(input: 1000, ordinal: 3), fixture.context(ordinal: 10),
            fixture.counter(input: 20, last: fixture.usage(input: 20), ordinal: 11),
        ])
        let statistics = await fixture.provider().statistics(for: fixture.account(home), days: 7)
        #expect(statistics.total == TokenCount(input: 40, output: 5, cacheRead: 10))
    }

    @Test func bucketsUseEventInstantsAndFixedLocalCalendar() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let today = calendar.startOfDay(for: CodexFixture.date)
        _ = try fixture.rollout(home, lines: [
            fixture.metadata(), fixture.context(),
            fixture.ledger("before", at: today.addingTimeInterval(-1)),
            fixture.ledger("after", at: today.addingTimeInterval(1)),
        ])
        let statistics = await fixture.provider(calendar: calendar).statistics(for: fixture.account(home), days: 2)
        #expect(statistics.days.count == 2)
        #expect(statistics.days.last?.day == today)
        #expect(statistics.days.allSatisfy { $0.total.total == 120 })
        let todayOnly = await fixture.provider(calendar: calendar).statistics(for: fixture.account(home), days: 1)
        #expect(todayOnly.total.total == 120)
    }

    @Test func appendPartialLineAndRewriteReplaceTheRightContributions() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.context(), fixture.ledger("first")])
        let provider = fixture.provider()
        let account = fixture.account(home)
        #expect(await provider.statistics(for: account, days: 7).total.total == 120)
        let second = fixture.ledger("second", input: 50, cached: 0, output: 5)
        let midpoint = second.index(second.startIndex, offsetBy: second.count / 2)
        try fixture.append([String(second[..<midpoint])], to: file)
        #expect(await provider.statistics(for: account, days: 7).total.total == 120)
        try fixture.append([String(second[midpoint...])], to: file)
        #expect(await provider.statistics(for: account, days: 7).total.total == 175)
        let reopened = fixture.provider()
        #expect(await reopened.statistics(for: account, days: 7).total.total == 175)
        let replacement = [fixture.metadata(), fixture.context(), fixture.ledger("replacement", input: 10, cached: 0, output: 1)].joined()
        try Data(replacement.utf8).write(to: file, options: .atomic)
        #expect(await provider.statistics(for: account, days: 7).total.total == 11)
        let sameSize = replacement.replacingOccurrences(of: "\"input_tokens\":10", with: "\"input_tokens\":20")
        try Data(sameSize.utf8).write(to: file)
        #expect(await provider.statistics(for: account, days: 7).total.total == 21)
    }

    @Test func concurrentRequestsShareHomeStateAndUnknownModelsStayUnknown() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        _ = try fixture.rollout(home, lines: [fixture.metadata(), fixture.ledger("response")])
        let provider = fixture.provider()
        let account = fixture.account(home)
        async let first = provider.statistics(for: account, days: 7)
        async let second = provider.statistics(for: account, days: 7)
        let pair = await (first, second)
        #expect(pair.0 == pair.1)
        #expect(pair.0.days.first?.byModel.keys.sorted() == ["unknown"])
        #expect(await provider.statistics(for: account, days: 0) == .empty)
    }

    @Test func lateLedgerCorrectsEarlierCheckpointAndUsesHistoricalContext() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let file = try fixture.rollout(home, lines: [fixture.metadata(), fixture.context("one", model: "model-one"), fixture.counter(input: 100)])
        let provider = fixture.provider()
        let account = fixture.account(home)
        #expect(await provider.statistics(for: account, days: 7).total.total == 100)
        try fixture.append([
            fixture.context("two", model: "model-two"),
            fixture.ledger("late", turn: "one", input: 50, cached: 10, output: 5),
            fixture.ledger("current", turn: "two", input: 20, cached: 0, output: 1),
        ], to: file)
        let statistics = await provider.statistics(for: account, days: 7)
        #expect(statistics.total.total == 76)
        #expect(statistics.days.first?.byModel["model-one"]?.total == 55)
        #expect(statistics.days.first?.byModel["model-two"]?.total == 21)
    }

    @Test func lifecycleTurnIDSurvivesAnOlderContextWithoutAnID() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        _ = try fixture.rollout(home, lines: [
            fixture.metadata(), fixture.event("task_started", turn: "turn"), fixture.context(nil),
            fixture.counter(input: 100), fixture.ledger("response", input: 50, cached: 0, output: 5),
        ])
        let statistics = await fixture.provider().statistics(for: fixture.account(home), days: 7)
        #expect(statistics.total.total == 55)
    }

    @Test func oversizedContentAndNestedUsageDoNotBecomeCharges() async throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let large = fixture.row("response_item", ["content": String(repeating: "ignored ", count: 400_000), "type": "token_usage_record", "usage": fixture.usage(input: 99999)])
        _ = try fixture.rollout(home, lines: [fixture.metadata(), fixture.context(), large, fixture.ledger("response")])
        let statistics = await fixture.provider().statistics(for: fixture.account(home), days: 7)
        #expect(statistics.total.total == 120)
    }
}
