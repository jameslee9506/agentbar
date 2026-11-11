import AgentBarCore
import SwiftUI

/// Every account, in the order of the menu bar. A checkbox shows or hides an account; dragging a row
/// moves it.
struct AccountSettingsView: View {
    /// A row held by the pointer.
    struct Drag {
        let id: AccountID
        /// From the top of the row to the pointer.
        let grab: CGFloat
        /// The pointer, in the coordinates of the visible part of the list.
        var pointer: CGFloat
    }

    let store: AccountStore
    let settings: AppSettings
    @State private var drag: Drag?
    @State private var rowFrames: [AccountID: CGRect] = [:]

    private static let list = "AccountSettingsView.list"
    private static let motion = Animation.easeOut(duration: 0.2)
    /// How close to an end of the visible part a dragged row scrolls the list.
    private static let scrollZone: CGFloat = 28

    init(store: AccountStore, settings: AppSettings, drag: Drag? = nil) {
        self.store = store
        self.settings = settings
        _drag = State(initialValue: drag)
    }

    var body: some View {
        let accounts = MenuBarAccounts.ordered(store.accounts, settings: settings)
        let frames = accounts.compactMap { rowFrames[$0.id] }
        let drag = drag
        SlimScrollView(maxHeight: 480, estimatedHeight: CGFloat(max(1, accounts.count) * 56)) { scroll in
            let reorder = Self.reorder(drag, accounts: accounts, frames: frames, offset: scroll.offset)
            VStack(spacing: 0) {
                if accounts.isEmpty {
                    Text("No accounts found").foregroundStyle(.secondary).padding(24)
                }
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, state in
                    row(state, at: index, in: accounts, reorder: reorder, scroll: scroll)
                }
            }
            .padding(.horizontal, 32)
            .coordinateSpace(.named(Self.list))
            .onPreferenceChange(RowFramesPreference.self) { rowFrames = $0 }
            .animation(Self.motion, value: reorder?.destination)
            .task(id: Self.scrollDirection(drag, scroll)) { await autoscroll(scroll) }
        }
    }

    private func row(
        _ state: AccountState, at index: Int, in accounts: [AccountState], reorder: ListReorder?,
        scroll: SlimScrollPosition
    ) -> some View {
        let isDragged = drag?.id == state.id
        return AccountRow(
            state: state, settings: settings,
            moveUp: index > 0 ? { move(accounts, from: index, to: index - 1) } : nil,
            moveDown: index < accounts.count - 1 ? { move(accounts, from: index, to: index + 1) } : nil
        )
        .background {
            if isDragged { DraggedRowBackground().padding(.horizontal, -12) }
        }
        .overlay(alignment: .top) {
            if !isDragged, (reorder?.position(of: index) ?? index) > 0 { Divider() }
        }
        .offset(y: reorder?.offset(of: index) ?? 0)
        .zIndex(isDragged ? 1 : 0)
        // The dragged row follows the pointer without delay.
        .transaction { if isDragged { $0.animation = nil } }
        // Behind the offset, so frames are where rows are laid out.
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: RowFramesPreference.self, value: [state.id: geometry.frame(in: .named(Self.list))]
                )
            }
        }
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(SlimScrollPosition.viewport))
                .onChanged { value in
                    if let drag {
                        guard drag.id == state.id else { return }
                        self.drag?.pointer = value.location.y
                    } else if let frame = rowFrames[state.id] {
                        let grab = value.startLocation.y + scroll.offset - frame.minY
                        self.drag = Drag(id: state.id, grab: grab, pointer: value.location.y)
                    }
                }
                .onEnded { value in
                    guard var drag, drag.id == state.id else { return }
                    drag.pointer = value.location.y
                    let frames = accounts.compactMap { rowFrames[$0.id] }
                    let reorder = Self.reorder(drag, accounts: accounts, frames: frames, offset: scroll.offset)
                    withAnimation(Self.motion) {
                        if let reorder, reorder.destination != reorder.source {
                            settings.setAccountOrder(reorder.apply(to: accounts.map(\.id)))
                        }
                        self.drag = nil
                    }
                }
        )
    }

    private func move(_ accounts: [AccountState], from index: Int, to destination: Int) {
        var ids = accounts.map(\.id)
        ids.swapAt(index, destination)
        withAnimation(Self.motion) { settings.setAccountOrder(ids) }
    }

    /// Scrolls while a dragged row is held near an end of the visible part, faster the further out
    /// the pointer is.
    private func autoscroll(_ scroll: SlimScrollPosition) async {
        let direction = Self.scrollDirection(drag, scroll)
        guard direction != 0 else { return }
        var offset = scroll.offset
        while !Task.isCancelled, let pointer = drag?.pointer {
            let depth = direction < 0 ? Self.scrollZone - pointer : pointer - (scroll.viewportHeight - Self.scrollZone)
            let step = min(max(depth, 4), 2 * Self.scrollZone) / 4
            offset = min(max(offset + CGFloat(direction) * step, 0), scroll.maxOffset)
            scroll.scroll(to: offset)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private static func reorder(
        _ drag: Drag?, accounts: [AccountState], frames: [CGRect], offset: CGFloat
    ) -> ListReorder? {
        guard let drag, frames.count == accounts.count,
              let source = accounts.firstIndex(where: { $0.id == drag.id }) else { return nil }
        return ListReorder(frames: frames, source: source, top: drag.pointer + offset - drag.grab)
    }

    private static func scrollDirection(_ drag: Drag?, _ scroll: SlimScrollPosition) -> Int {
        guard let drag else { return 0 }
        if drag.pointer < scrollZone, scroll.offset > 0 { return -1 }
        if drag.pointer > scroll.viewportHeight - scrollZone, scroll.offset < scroll.maxOffset { return 1 }
        return 0
    }
}

/// Raises a dragged row above the list.
private struct DraggedRowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        shape.fill(.background)
            // Raised surfaces are lighter in the dark.
            .overlay { shape.fill(.white.opacity(colorScheme == .dark ? 0.07 : 0)) }
            .overlay { shape.strokeBorder(.separator) }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

private struct RowFramesPreference: PreferenceKey {
    static let defaultValue: [AccountID: CGRect] = [:]

    static func reduce(value: inout [AccountID: CGRect], nextValue: () -> [AccountID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
