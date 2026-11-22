@testable import AgentBar
import AgentBarCore
import Foundation
import Testing

struct DisplayFormatTests {
    @Test func tokenAbbreviations() {
        #expect(DisplayFormat.tokens(0) == "0")
        #expect(DisplayFormat.tokens(999) == "999")
        #expect(DisplayFormat.tokens(1_000) == "1K")
        #expect(DisplayFormat.tokens(1_234_567) == "1.2M")
        #expect(DisplayFormat.tokens(2_000_000_000) == "2B")
    }

    @Test func durationsAndResetTimes() {
        #expect(DisplayFormat.duration(-10) == "<1m")
        #expect(DisplayFormat.duration(120) == "2m")
        #expect(DisplayFormat.duration(3_600) == "1h")
        #expect(DisplayFormat.duration(7_680) == "2h 8m")
        #expect(DisplayFormat.duration(93_600) == "1d 2h")
        #expect(DisplayFormat.reset(nil, now: TestFixtures.date) == "—")
        #expect(DisplayFormat.reset(TestFixtures.date, now: TestFixtures.date) == "Now")
    }

    @Test func sessionTimesAndTokenSummaries() {
        let now = TestFixtures.date
        let working = AgentSession(id: "a", state: .working, since: now.addingTimeInterval(-480))
        #expect(DisplayFormat.sessionTime(working, now: now) == "8m")
        #expect(DisplayFormat.sessionTime(AgentSession(id: "b", state: .working), now: now) == "Working")
        #expect(DisplayFormat.sessionTime(AgentSession(id: "c", state: .idle, since: now), now: now) == "Idle")
        let today = Calendar.current.startOfDay(for: now)
        let statistics = UsageStatistics(days: [-7, -6, 0].map { offset in
            DailyUsage(day: today.addingTimeInterval(Double(offset) * 86_400 + 3_600), byModel: ["test-model": TokenCount(input: 1_000)])
        })
        #expect(DisplayFormat.tokenSummary(statistics, now: now) == "Tokens  1K today · 2K in 7d")
        #expect(DisplayFormat.tokenSummary(.empty, now: now) == "Tokens  0 today · 0 in 7d")
    }

    @Test func pathsPercentagesAndQuietErrors() {
        #expect(DisplayFormat.directory(nil) == "Session")
        #expect(DisplayFormat.directory("/synthetic/project/") == "project")
        #expect(DisplayFormat.directory("/") == "/")
        #expect(DisplayFormat.percent(43.2) == "43%")
        #expect(DisplayFormat.percent(120) == "100%")
        #expect(DisplayFormat.percent(.nan) == "—")
        #expect(DisplayFormat.error(.sessionExpired) == "Sign-in expired")
        #expect(DisplayFormat.error(.unavailable("Detailed diagnostic")) == "Usage unavailable")
    }
}
