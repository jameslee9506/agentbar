@testable import AgentBar
import AppKit
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
struct SlimScrollViewTests {
    @Test func measuresItsContentAndScrollsToAnOffset() async throws {
        _ = NSApplication.shared
        let seen = SeenPosition()
        let view = NSHostingView(rootView: SlimScrollView(maxHeight: 100, estimatedHeight: 50) { position in
            let _ = seen.position = position
            Color.clear.frame(height: 1_000)
        }.frame(width: 200))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.layoutSubtreeIfNeeded()

        #expect(await TestWait.until { seen.position?.contentHeight == 1_000 })
        #expect(seen.position?.viewportHeight == 100)
        #expect(seen.position?.maxOffset == 900)
        #expect(seen.position?.offset == 0)
        seen.position?.scroll(to: 450)
        #expect(await TestWait.until { abs((seen.position?.offset ?? 0) - 450) < 1 })
        seen.position?.scroll(to: 5_000)
        #expect(await TestWait.until { abs((seen.position?.offset ?? 0) - 900) < 1 })
        seen.position?.scroll(to: -5)
        #expect(await TestWait.until { abs(seen.position?.offset ?? 1) < 1 })
    }
}

@MainActor
private final class SeenPosition {
    var position: SlimScrollPosition?
}
