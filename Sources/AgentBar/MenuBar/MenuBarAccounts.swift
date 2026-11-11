import AgentBarCore
import Foundation

enum MenuBarAccounts {
    /// Every account in the order of the menu bar: as arranged in Settings, then the accounts never
    /// arranged in their default order.
    @MainActor
    static func ordered(_ accounts: [AccountState], settings: AppSettings) -> [AccountState] {
        let rank = Dictionary(
            settings.accountOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min
        )
        return accounts.sorted {
            let (lhs, rhs) = (rank[$0.id.description] ?? .max, rank[$1.id.description] ?? .max)
            return lhs == rhs ? AccountState.defaultOrder($0, $1) : lhs < rhs
        }
    }

    @MainActor
    static func visible(_ accounts: [AccountState], settings: AppSettings, accountID: AccountID? = nil) -> [AccountState] {
        ordered(accounts, settings: settings).filter {
            settings.isVisible($0.id) && (accountID == nil || $0.id == accountID)
        }
    }
}
