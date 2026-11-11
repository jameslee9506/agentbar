@testable import AgentBar
import AgentBarCore
import Foundation
import Testing

struct StatisticsReportTests {
    @Test func selectedRangeAggregatesByAccountOrModelAndExcludesOtherDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let today = calendar.startOfDay(for: TestFixtures.date)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let old = try #require(calendar.date(byAdding: .day, value: -7, to: today))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        var a = AccountState(account: TestFixtures.account("alpha"))
        a.statistics = UsageStatistics(days: [
            DailyUsage(day: old, byModel: ["A": TokenCount(input: 900)]),
            DailyUsage(day: yesterday, byModel: ["A": TokenCount(input: 10, output: 5), "B": TokenCount(cacheRead: 20)]),
            DailyUsage(day: today, byModel: ["A": TokenCount(input: 20, cacheWrite: 3)]),
            DailyUsage(day: tomorrow, byModel: ["A": TokenCount(input: 800)]),
        ])
        var b = AccountState(account: TestFixtures.account("beta", kind: .codex))
        b.statistics = UsageStatistics(days: [DailyUsage(day: today, byModel: ["C": TokenCount(output: 7)])])
        let all = StatisticsReport(accounts: [a, b], selectedAccount: nil, days: 7, now: TestFixtures.date, calendar: calendar)
        #expect(all.rows.count == 2)
        #expect(all.total.total == 65)
        #expect(all.segments.count == 3)
        let models = StatisticsReport(accounts: [a, b], selectedAccount: a.id, days: 7, now: TestFixtures.date, calendar: calendar)
        #expect(models.rows.map(\.name) == ["A", "B"])
        #expect(models.total == TokenCount(input: 30, output: 5, cacheRead: 20, cacheWrite: 3))
        #expect(models.segments.count == 3)
        let long = StatisticsReport(accounts: [a, b], selectedAccount: a.id, days: 30, now: TestFixtures.date, calendar: calendar)
        #expect(long.total.total == 958)
    }
}
