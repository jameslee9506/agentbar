import Foundation

/// Identifies an account by provider and config home, written as `claude:.claude-work`.
public struct AccountID: Hashable, Codable, Sendable, Comparable, LosslessStringConvertible {
    public let provider: ProviderKind
    /// The config home directory name, unique within a provider.
    public let home: String

    public init(provider: ProviderKind, home: String) {
        self.provider = provider
        self.home = home
    }

    public init?(_ description: String) {
        let parts = description.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let provider = ProviderKind(rawValue: String(parts[0])) else { return nil }
        self.init(provider: provider, home: String(parts[1]))
    }

    public var description: String { "\(provider.rawValue):\(home)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.provider, lhs.home) < (rhs.provider, rhs.home)
    }
}

/// One account signed in to one config home.
public struct Account: Identifiable, Hashable, Sendable {
    public let id: AccountID
    /// Short label: the config home suffix (`work` for `.claude-work`), or the provider's command
    /// name for the default home.
    public let name: String
    public let home: URL
    public let email: String?
    /// Subscription plan as shown to the user, for example "Max" or "Plus".
    public let plan: String?

    public init(id: AccountID, name: String, home: URL, email: String? = nil, plan: String? = nil) {
        self.id = id
        self.name = name
        self.home = home
        self.email = email
        self.plan = plan
    }
}
