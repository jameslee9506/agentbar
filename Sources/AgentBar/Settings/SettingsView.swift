import SwiftUI

struct SettingsView: View {
    let store: AccountStore
    let settings: AppSettings
    let loginItem: LoginItemState
    @State var selection: SettingsTab = .general
    var onSizeChange: ((CGSize) -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Picker("Settings", selection: $selection) {
                Text("General").tag(SettingsTab.general)
                Text("Accounts").tag(SettingsTab.accounts)
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 220)
            switch selection {
            case .general:
                GeneralSettingsView(settings: settings, loginItem: loginItem)
            case .accounts:
                AccountSettingsView(store: store, settings: settings)
            }
        }
        .padding(16)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(.background)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: SettingsWindowSizePreference.self, value: geometry.size)
            }
        }
        .onPreferenceChange(SettingsWindowSizePreference.self) { onSizeChange?($0) }
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }
}
