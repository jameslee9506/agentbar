import AgentBarCore
import Foundation
import Testing

struct UsageTests {
    @Test func weeklyIsTheWeeklyWindowOfTheWholeSubscription() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = date.addingTimeInterval(60)
        let others = [
            UsageWindow(id: "session", title: "5h", usedPercent: 43),
            UsageWindow(id: "weekly.opus", title: "Opus", usedPercent: 91),
        ]
        let weekly = UsageWindow(id: "weekly", title: "Week", usedPercent: 68, resetsAt: reset)
        let snapshot = UsageSnapshot(windows: others + [weekly], capturedAt: date)
        #expect(snapshot.weekly == weekly)
        #expect(snapshot.rolledForward(to: reset).weekly?.usedPercent == 0)
        #expect(UsageSnapshot(windows: others, capturedAt: date).weekly == nil)
    }
}
