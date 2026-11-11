import AgentBarCore
import Foundation

enum MenuBarAccounts {
    @MainActor
    static func visible(_ accounts: [AccountState], settings: AppSettings, accountID: AccountID? = nil) -> [AccountState] {
        accounts.filter {
            settings.isVisible($0.id) && (accountID == nil || $0.id == accountID)
        }.sorted {
            if $0.id.provider != $1.id.provider { return $0.id.provider < $1.id.provider }
            let order = $0.account.name.localizedStandardCompare($1.account.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
