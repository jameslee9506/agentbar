import SwiftUI

struct AccountSettingsView: View {
    let store: AccountStore
    let settings: AppSettings
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if store.accounts.isEmpty {
                    Text("No accounts found").foregroundStyle(.secondary).padding(24)
                }
                ForEach(store.accounts) { state in
                    if state.id != store.accounts.first?.id { Divider() }
                    HStack(spacing: 10) {
                        Toggle("Show \(state.account.name)", isOn: Binding(
                            get: { settings.isVisible(state.id) },
                            set: { settings.setVisible($0, for: state.id) }
                        ))
                        .labelsHidden().toggleStyle(.checkbox)
                        ProviderMark(kind: state.id.provider)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(state.account.name).font(.system(size: 12, weight: .medium))
                            if let email = state.account.email {
                                Text(email).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 6)
                        if let plan = state.account.plan {
                            Text(plan).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: AccountListHeightPreference.self, value: geometry.size.height)
                }
            }
        }
        .frame(height: min(480, contentHeight > 0 ? contentHeight : CGFloat(max(1, store.accounts.count) * 56)))
        .onPreferenceChange(AccountListHeightPreference.self) { contentHeight = $0 }
    }
}
