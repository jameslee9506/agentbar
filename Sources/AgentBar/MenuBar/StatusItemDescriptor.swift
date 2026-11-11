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
    let accessibilityLabel: String

    var displayedName: String? {
        name.map { $0.count > 16 ? String($0.prefix(15)) + "…" : $0 }
    }

    var accountID: AccountID? {
        if case .account(let id) = id { return id }
        return nil
    }
}
