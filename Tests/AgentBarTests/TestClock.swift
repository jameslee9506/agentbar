import Foundation

@MainActor
final class TestClock {
    var date = TestFixtures.date
    func advance(_ seconds: TimeInterval) { date.addTimeInterval(seconds) }
}
