import AgentBarCore

struct StatusItemDescriptor: Identifiable, Equatable {
    enum ID: Hashable {
        case account(AccountID)
        case overview
    }

    let id: ID
    let provider: ProviderKind?
    let name: String?
    let workingCount: Int
    /// Which number follows the name.
    let number: MenuBarNumber
    /// The weekly usage that follows the name, for example "68%": `nil` unless `number` asks for it and
    /// the usage is known.
    let weeklyUsage: String?
    let accessibilityLabel: String

    var displayedName: String? {
        name.map { $0.count > 16 ? String($0.prefix(15)) + "…" : $0 }
    }

    /// One number at most follows the name.
    var displayedNumber: String? {
        switch number {
        case .workingSessions: workingCount > 0 ? String(workingCount) : nil
        case .weeklyUsage: weeklyUsage
        case .off: nil
        }
    }

    var accountID: AccountID? {
        if case .account(let id) = id { return id }
        return nil
    }
}
