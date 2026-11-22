import AgentBarCore
import Foundation

enum DisplayFormat {
    static let locale = Locale(identifier: "en_US")

    static func tokens(_ value: Int) -> String {
        let magnitude = abs(Double(value))
        let divisor: Double
        let suffix: String
        switch magnitude {
        case 1_000_000_000...: (divisor, suffix) = (1_000_000_000, "B")
        case 1_000_000...: (divisor, suffix) = (1_000_000, "M")
        case 1_000...: (divisor, suffix) = (1_000, "K")
        default: return String(value)
        }
        let scaled = Double(value) / divisor
        return scaled.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + suffix
    }

    /// The tokens of today and of the last seven days, today included.
    static func tokenSummary(_ statistics: UsageStatistics, now: Date) -> String {
        let today = Calendar.current.startOfDay(for: now)
        let start = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? now
        let todayTokens = statistics.days.filter { $0.day >= today && $0.day < tomorrow }.reduce(0) { $0 + $1.total.total }
        let weekTokens = statistics.days.filter { $0.day >= start && $0.day < tomorrow }.reduce(0) { $0 + $1.total.total }
        return "Tokens  \(tokens(todayTokens)) today · \(tokens(weekTokens)) in 7d"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "—" }
        let minutes = max(0, Int(seconds / 60))
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 {
            return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
        }
        let days = hours / 24
        return hours % 24 == 0 ? "\(days)d" : "\(days)d \(hours % 24)h"
    }

    static func reset(_ date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "Now" }
        return duration(remaining < 60 ? remaining : ceil(remaining / 60) * 60)
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(locale))
    }

    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return "\(Int(min(100, max(0, value)).rounded()))%"
    }

    static func directory(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "Session" }
        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.isEmpty ? "/" : last
    }

    /// How long a session has been working, or that it is idle.
    static func sessionTime(_ session: AgentSession, now: Date) -> String {
        guard session.state == .working else { return "Idle" }
        return session.since.map { duration(now.timeIntervalSince($0)) } ?? "Working"
    }

    static func error(_ error: UsageError) -> String {
        switch error {
        case .signedOut: "Signed out"
        case .sessionExpired: "Sign-in expired"
        case .rateLimited: "Rate limited"
        case .unavailable: "Usage unavailable"
        }
    }

    static func status(_ state: AccountState, now: Date) -> String? {
        if let error = state.usageError {
            return state.usage == nil ? Self.error(error) : "Stale · \(Self.error(error))"
        }
        if state.isStale { return "Cached · \(duration(now.timeIntervalSince(state.usage!.capturedAt))) ago" }
        return nil
    }
}
