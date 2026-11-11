import Foundation

/// Token counts with cached input separated, comparable across providers.
public struct TokenCount: Hashable, Codable, Sendable {
    /// Input tokens that were not served from cache.
    public var input: Int
    /// Output tokens, including reasoning.
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }

    public static let zero = TokenCount()

    public var total: Int { input + output + cacheRead + cacheWrite }

    public static func + (lhs: Self, rhs: Self) -> Self {
        TokenCount(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite
        )
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }
}

/// One account's token usage on one local calendar day.
public struct DailyUsage: Identifiable, Hashable, Codable, Sendable {
    /// Start of the day in the user's current calendar.
    public let day: Date
    /// Keyed by the model name as the provider reports it.
    public let byModel: [String: TokenCount]

    public init(day: Date, byModel: [String: TokenCount]) {
        self.day = day
        self.byModel = byModel
    }

    public var id: Date { day }
    public var total: TokenCount { byModel.values.reduce(.zero, +) }
}

/// Daily token usage of one account over a range of days.
public struct UsageStatistics: Hashable, Codable, Sendable {
    /// Ascending by day; days without usage are omitted.
    public let days: [DailyUsage]

    public init(days: [DailyUsage]) {
        self.days = days
    }

    public static let empty = UsageStatistics(days: [])

    public var total: TokenCount { days.reduce(.zero) { $0 + $1.total } }
}
