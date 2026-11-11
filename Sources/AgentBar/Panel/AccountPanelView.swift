import AgentBarCore
import SwiftUI

struct AccountPanelView: View {
    let store: AccountStore
    let settings: AppSettings
    let accountID: AccountID?
    let actions: PanelActions
    @State private var measuredHeight: CGFloat = 0

    var accounts: [AccountState] {
        MenuBarAccounts.visible(store.accounts, settings: settings, accountID: accountID)
    }

    private var contentHeight: CGFloat {
        guard !accounts.isEmpty else { return 82 }
        return accounts.reduce(0) { height, state in
            let windows = max(1, state.usage?.windows.count ?? 1)
            let statusHeight: CGFloat = state.usageError != nil || state.isStale ? 22 : 0
            let sessionHeight: CGFloat = state.activity.sessions.isEmpty ? 0 : CGFloat(state.activity.sessions.count * 20 + 8)
            return height + 80 + CGFloat(windows * 22) + statusHeight + sessionHeight
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if accounts.isEmpty {
                        Text(store.hasDiscoveredAccounts ? "No visible accounts" : "Finding accounts…")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            VStack(spacing: 0) {
                                ForEach(accounts) { account in
                                    if account.id != accounts.first?.id { Divider().padding(.horizontal, 12) }
                                    AccountSectionView(state: account, now: context.date)
                                }
                            }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: PanelHeightPreference.self, value: geometry.size.height)
                    }
                }
            }
            .frame(height: min(560, measuredHeight > 0 ? measuredHeight : contentHeight))
            .onPreferenceChange(PanelHeightPreference.self) { measuredHeight = $0 }
            Divider()
            PanelFooterView(isRefreshing: store.isRefreshing, actions: actions)
        }
        .font(.system(size: 12))
        .frame(width: 300)
        .background(.background)
    }
}
