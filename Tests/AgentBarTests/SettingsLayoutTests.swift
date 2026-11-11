@testable import AgentBar
import AppKit
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
struct SettingsLayoutTests {
    @Test(arguments: [4, 30])
    func reportedWindowSizeMatchesCappedLayout(accountCount: Int) async throws {
        _ = NSApplication.shared
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accounts = (1...accountCount).map { TestFixtures.account("account-\($0)") }
        let store = AccountStore(providers: [TestProvider(kind: .claude, accounts: accounts)])
        defer { store.stop() }
        await store.refresh(reason: .launch)

        var reportedSizes: [CGSize] = []
        let view = NSHostingView(rootView: SettingsView(
            store: store, settings: AppSettings(defaults: defaults), loginItem: LoginItemState(preview: true),
            selection: .accounts, onSizeChange: { reportedSizes.append($0) }
        ))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: view.fittingSize),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        #expect(await TestWait.until { reportedSizes.last?.height ?? 0 > 0 })
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()

        let reported = try #require(reportedSizes.last)
        let fitting = view.fittingSize
        #expect(abs(reported.width - fitting.width) <= 1)
        #expect(abs(reported.height - fitting.height) <= 1)
        // The list is capped at 480 points; only the tab picker, spacing, and padding remain.
        #expect(reportedSizes.allSatisfy { $0.height <= 580 })
        #expect(fitting.width == 460)
        if accountCount == 30 {
            #expect(fitting.height >= 480)
            #expect(fitting.height <= 580)
        } else {
            #expect(fitting.height < 480)
        }
    }
}
