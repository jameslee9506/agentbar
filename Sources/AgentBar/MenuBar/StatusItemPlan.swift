import AgentBarCore
import Foundation

enum StatusItemPlan {
    @MainActor
    static func make(accounts: [AccountState], settings: AppSettings, now: Date) -> [StatusItemDescriptor] {
        let visible = MenuBarAccounts.visible(accounts, settings: settings)
        // Keep Settings reachable before discovery and when every account is hidden.
        if settings.menuBarMode == .combined || visible.isEmpty {
            return [descriptor(
                .overview, provider: nil, name: nil, title: "AgentBar", accounts: visible, settings: settings, now: now
            )]
        }
        return visible.map { state in
            descriptor(
                .account(state.id), provider: state.id.provider,
                name: settings.showAccountNames ? state.account.name : nil,
                title: "\(state.id.provider.displayName), \(state.account.name)",
                accounts: [state], settings: settings, now: now
            )
        }
    }

    /// When a shown weekly usage next falls to zero because its window resets. The items change then
    /// without a change in the accounts or the settings.
    @MainActor
    static func nextReset(accounts: [AccountState], settings: AppSettings, after now: Date) -> Date? {
        guard settings.menuBarNumber == .weeklyUsage else { return nil }
        return MenuBarAccounts.visible(accounts, settings: settings)
            .compactMap { $0.usage?.weekly?.resetsAt }.filter { $0 > now }.min()
    }

    /// The item that stands for `accounts`.
    @MainActor
    private static func descriptor(
        _ id: StatusItemDescriptor.ID, provider: ProviderKind?, name: String?, title: String,
        accounts: [AccountState], settings: AppSettings, now: Date
    ) -> StatusItemDescriptor {
        let working = accounts.reduce(0) { $0 + $1.activity.workingCount }
        // As the panel shows it at `now`. An item that stands for several accounts shows the highest usage.
        let usage = settings.menuBarNumber == .weeklyUsage
            ? accounts.compactMap { $0.snapshot(at: now)?.weekly?.usedPercent }.filter(\.isFinite).max() : nil
        let weeklyUsage = usage.map(DisplayFormat.percent)
        return StatusItemDescriptor(
            id: id, provider: provider, name: name, workingCount: working,
            number: settings.menuBarNumber, weeklyUsage: weeklyUsage,
            accessibilityLabel: title + (working > 0 ? ", \(working) working" : "")
                + (weeklyUsage.map { ", weekly usage \(accounts.count > 1 ? "up to " : "")\($0)" } ?? "")
        )
    }
}
