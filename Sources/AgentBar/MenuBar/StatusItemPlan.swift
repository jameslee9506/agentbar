enum StatusItemPlan {
    @MainActor
    static func make(accounts: [AccountState], settings: AppSettings) -> [StatusItemDescriptor] {
        let visible = MenuBarAccounts.visible(accounts, settings: settings)
        // Keep Settings reachable before discovery and when every account is hidden.
        if settings.menuBarMode == .combined || visible.isEmpty {
            let working = visible.reduce(0) { $0 + $1.activity.workingCount }
            return [StatusItemDescriptor(
                id: .overview, provider: nil, name: nil, workingCount: working,
                accessibilityLabel: working > 0 ? "AgentBar, \(working) working" : "AgentBar"
            )]
        }
        return visible.map { state in
            let working = state.activity.workingCount
            return StatusItemDescriptor(
                id: .account(state.id), provider: state.id.provider,
                name: settings.showAccountNames ? state.account.name : nil, workingCount: working,
                accessibilityLabel: "\(state.id.provider.displayName), \(state.account.name)"
                    + (working > 0 ? ", \(working) working" : "")
            )
        }
    }
}
