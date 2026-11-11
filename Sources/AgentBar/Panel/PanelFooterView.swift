import SwiftUI

struct PanelFooterView: View {
    let isRefreshing: Bool
    let actions: PanelActions

    var body: some View {
        HStack(spacing: 12) {
            Button(action: actions.refresh) { Image(systemName: "arrow.clockwise") }
                .help("Refresh").accessibilityLabel("Refresh").disabled(isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
            Button(action: actions.statistics) { Image(systemName: "chart.bar") }
                .help("Statistics").accessibilityLabel("Statistics")
            Button(action: actions.settings) { Image(systemName: "gearshape") }
                .help("Settings").accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button(action: actions.quit) { Image(systemName: "power") }
                .help("Quit AgentBar").accessibilityLabel("Quit AgentBar")
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
