import SwiftUI

/// A vertical scroll view as tall as its content, up to `maxHeight`. Its scroller is a slim thumb at
/// its trailing edge, whatever the scroller style of the system; dragging the thumb scrolls.
struct SlimScrollView<Content: View>: View {
    let maxHeight: CGFloat
    /// The height until the content has been measured.
    let estimatedHeight: CGFloat
    @ViewBuilder let content: (SlimScrollPosition) -> Content
    @State private var contentFrame: CGRect = .zero

    var body: some View {
        let height = min(maxHeight, contentFrame.height > 0 ? contentFrame.height : estimatedHeight)
        ScrollViewReader { reader in
            let position = SlimScrollPosition(
                offset: -contentFrame.minY, contentHeight: contentFrame.height, viewportHeight: height, reader: reader
            )
            ScrollView {
                content(position)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ContentFramePreference.self,
                                value: geometry.frame(in: .named(SlimScrollPosition.viewport))
                            )
                        }
                    }
                    .id(SlimScrollPosition.content)
            }
            .scrollIndicators(.never)
            .coordinateSpace(.named(SlimScrollPosition.viewport))
            .overlay(alignment: .topTrailing) { SlimScrollThumb(position: position) }
        }
        .frame(height: height)
        .onPreferenceChange(ContentFramePreference.self) { contentFrame = $0 ?? .zero }
    }
}

/// How far a `SlimScrollView` is scrolled, and a way to scroll it.
struct SlimScrollPosition {
    /// The coordinate space of the visible part of a `SlimScrollView`.
    static let viewport = "SlimScrollView.viewport"
    fileprivate static let content = "SlimScrollView.content"

    /// How far the content is scrolled up: beyond `0...maxOffset` while it bounces at an end.
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    fileprivate let reader: ScrollViewProxy

    var maxOffset: CGFloat { max(0, contentHeight - viewportHeight) }

    /// Scrolls the content up by `offset`, kept within `0...maxOffset`.
    func scroll(to offset: CGFloat) {
        guard maxOffset > 0 else { return }
        // Aligning the same fraction of the content and of the visible part scrolls by that fraction
        // of `maxOffset`.
        reader.scrollTo(Self.content, anchor: UnitPoint(x: 0, y: min(max(offset, 0), maxOffset) / maxOffset))
    }
}

/// The scroller of a `SlimScrollView`, shown while the content does not fit.
private struct SlimScrollThumb: View {
    let position: SlimScrollPosition
    @State private var isHovered = false
    @State private var dragStart: CGFloat?

    private static let inset: CGFloat = 3
    private static let minimumLength: CGFloat = 24

    var body: some View {
        if position.maxOffset > 0 {
            let track = position.viewportHeight - 2 * Self.inset
            let length = min(track, max(Self.minimumLength, track * position.viewportHeight / position.contentHeight))
            let progress = min(max(position.offset / position.maxOffset, 0), 1)
            let isActive = isHovered || dragStart != nil
            Capsule()
                .fill(.primary.opacity(isActive ? 0.4 : 0.2))
                .frame(width: isActive ? 7 : 5, height: length)
                .frame(width: 12, alignment: .trailing)
                .padding(.trailing, Self.inset)
                .contentShape(Rectangle())
                .offset(y: Self.inset + (track - length) * progress)
                .onHover { isHovered = $0 }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(SlimScrollPosition.viewport))
                        .onChanged { value in
                            let start = dragStart ?? position.offset
                            dragStart = start
                            let travel = max(1, track - length)
                            position.scroll(to: start + value.translation.height * position.maxOffset / travel)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .animation(.easeOut(duration: 0.15), value: isActive)
                .accessibilityHidden(true)
        }
    }
}

private struct ContentFramePreference: PreferenceKey {
    static let defaultValue: CGRect? = nil

    /// Views that do not report a frame report the default value.
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}
