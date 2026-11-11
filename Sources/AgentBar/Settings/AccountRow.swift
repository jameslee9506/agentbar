import SwiftUI

struct AccountRow: View {
    let state: AccountState
    let settings: AppSettings
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?

    var body: some View {
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
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary)
                .grabPointer()
                .help("Drag to reorder")
                .accessibilityLabel("Reorder \(state.account.name)")
                .accessibilityActions {
                    if let moveUp { Button("Move Up", action: moveUp) }
                    if let moveDown { Button("Move Down", action: moveDown) }
                }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private extension View {
    /// The open hand over something to drag, on systems that have it.
    @ViewBuilder
    func grabPointer() -> some View {
        if #available(macOS 15, *) {
            pointerStyle(.grabIdle)
        } else {
            self
        }
    }
}
