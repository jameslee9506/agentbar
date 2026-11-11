import Foundation

struct UsageCooldown {
    var lastAttempt: Date?
    var retryAfter: Date?

    func isActive(at date: Date) -> Bool {
        lastAttempt.map { $0.addingTimeInterval(60) > date } == true
            || retryAfter.map { $0 > date } == true
    }
}
