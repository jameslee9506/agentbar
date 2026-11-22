import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    let loginItem: LoginItemState
    let commandLine: CommandLineToolState

    var body: some View {
        Form {
            Picker("Menu bar", selection: $settings.menuBarMode) {
                ForEach(MenuBarMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            Toggle("Show account names", isOn: $settings.showAccountNames)
                .disabled(settings.menuBarMode == .combined)
            Picker("Menu bar number", selection: $settings.menuBarNumber) {
                ForEach(MenuBarNumber.allCases) { number in Text(number.title).tag(number) }
            }
            Picker("Refresh every", selection: $settings.refreshMinutes) {
                ForEach(AppSettings.refreshIntervals, id: \.self) { interval in
                    Text("\(interval) minutes").tag(interval)
                }
            }
            Toggle("Launch at login", isOn: Binding(
                get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }
            ))
            .disabled(!loginItem.isAvailable)
            if loginItem.needsApproval {
                Button("Allow in Login Items") { loginItem.openLoginSettings() }
                    .font(.callout)
            }
            Toggle("“agentbar” terminal command", isOn: Binding(
                get: { commandLine.isInstalled }, set: { commandLine.setInstalled($0) }
            ))
            .disabled(!commandLine.isAvailable || commandLine.isChanging)
            .help("Shows the accounts in a terminal. Installed as \(CommandLineTool.path).")
            if let problem = commandLine.problem {
                Text(problem).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.columns)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
    }
}
