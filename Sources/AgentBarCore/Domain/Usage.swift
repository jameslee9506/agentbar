import Foundation

/// One rate-limit window of a subscription.
public struct UsageWindow: Identifiable, Hashable, Codable, Sendable {
    /// Stable within an account, for example `session`, `weekly`, `weekly.opus`. The weekly window of the
    /// whole subscription is always `weekly`.
    public let id: String
    /// Short label, for example "5h", "Week", "Opus".
    public let title: String
    /// 0 through 100.
    public let usedPercent: Double
    /// When the window resets, if the service reports it.
    public let resetsAt: Date?

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date? = nil) {
        self.id = id
        self.title = title
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.resetsAt = resetsAt
    }

    /// The window as of `date`: once its reset time has passed it is empty until fresh data arrives.
    public func rolledForward(to date: Date) -> UsageWindow {
        guard let resetsAt, resetsAt <= date else { return self }
        return UsageWindow(id: id, title: title, usedPercent: 0)
    }
}

/// The usage of one account at one moment.
public struct UsageSnapshot: Hashable, Codable, Sendable {
    /// Most constraining first: the short window, then weekly, then model-specific windows.
    public let windows: [UsageWindow]
    /// When the service produced this data.
    public let capturedAt: Date

    public init(windows: [UsageWindow], capturedAt: Date) {
        self.windows = windows
        self.capturedAt = capturedAt
    }

    /// The weekly window of the whole subscription, if the account has one.
    public var weekly: UsageWindow? { windows.first { $0.id == "weekly" } }

    /// The snapshot with every window rolled forward to `date`.
    public func rolledForward(to date: Date) -> UsageSnapshot {
        UsageSnapshot(windows: windows.map { $0.rolledForward(to: date) }, capturedAt: capturedAt)
    }
}

/// Why live usage could not be read. Never fatal: the app keeps the last snapshot and retries.
public enum UsageError: Error, Hashable, Sendable {
    /// The config home has no credentials.
    case signedOut
    /// The stored access token expired. The CLI renews it the next time it runs.
    case sessionExpired
    /// The service asked to slow down; do not retry before the interval passes.
    case rateLimited(retryAfter: TimeInterval?)
    /// Network failure or unexpected response, with a short diagnostic that contains no secrets.
    case unavailable(String)
}
