import Foundation

/// One open CLI session.
public struct AgentSession: Identifiable, Hashable, Sendable {
    public enum State: String, Sendable {
        /// A turn is running.
        case working
        /// Open, and not running a turn as far as the provider can tell.
        case idle
    }

    /// Stable for the lifetime of the session.
    public let id: String
    public let state: State
    /// The session's working directory.
    public let directory: String?
    /// When the current state began.
    public let since: Date?

    public init(id: String, state: State, directory: String? = nil, since: Date? = nil) {
        self.id = id
        self.state = state
        self.directory = directory
        self.since = since
    }
}

/// The live sessions of one account.
public struct AccountActivity: Hashable, Sendable {
    /// Working sessions first, then by how recently the state began.
    public let sessions: [AgentSession]

    public init(sessions: [AgentSession]) {
        self.sessions = sessions
    }

    public static let none = AccountActivity(sessions: [])

    public var workingCount: Int { sessions.count { $0.state == .working } }
    public var isWorking: Bool { workingCount > 0 }
}
