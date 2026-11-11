import Foundation

/// The agent CLIs AgentBar monitors.
public enum ProviderKind: String, Codable, Sendable, CaseIterable, Comparable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// The command that selects the provider's default config home.
    public var commandName: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    private var sortIndex: Int {
        switch self {
        case .claude: 0
        case .codex: 1
        }
    }
}

/// Everything the app needs from one provider.
///
/// A provider is a read-only observer of the accounts on this machine: it never writes to a config
/// home or the Keychain and never refreshes tokens. All methods may be called concurrently.
public protocol AccountProvider: Sendable {
    var kind: ProviderKind { get }

    /// Accounts found in local config homes, sorted by name. Cheap enough to call on every refresh.
    func accounts() async -> [Account]

    /// The last usage known locally, without touching the network. `nil` when nothing is cached.
    func cachedUsage(for account: Account) async -> UsageSnapshot?

    /// Current subscription usage from the provider's service.
    func usage(for account: Account) async throws(UsageError) -> UsageSnapshot

    /// Live sessions of the given accounts. Emits the full state at once, then again after every
    /// change, until the consuming task is cancelled or the stream is released. Every given account
    /// has an entry.
    func activity(for accounts: [Account]) -> AsyncStream<[AccountID: AccountActivity]>

    /// Tokens per local calendar day over the last `days` days, today included. Best effort:
    /// unreadable history yields fewer days, never an error.
    func statistics(for account: Account, days: Int) async -> UsageStatistics
}
