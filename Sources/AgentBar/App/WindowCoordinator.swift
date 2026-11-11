import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private let store: AccountStore
    private let settings: AppSettings
    private let loginItem: LoginItemState
    private var settingsWindow: NSWindow?
    private var statisticsWindow: NSWindow?

    init(store: AccountStore, settings: AppSettings, loginItem: LoginItemState) {
        self.store = store
        self.settings = settings
        self.loginItem = loginItem
    }

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "AgentBar Settings", size: NSSize(width: 460, height: 220), resizable: false,
                content: SettingsView(store: store, settings: settings, loginItem: loginItem, onSizeChange: { [weak self] size in
                    self?.resizeSettings(to: size)
                })
            )
            if let size = settingsWindow?.contentView?.fittingSize { resizeSettings(to: size) }
        }
        loginItem.refresh()
        present(settingsWindow)
    }

    func showStatistics() {
        if statisticsWindow == nil {
            statisticsWindow = makeWindow(
                title: "Statistics", size: StatisticsLayout.preferredSize, resizable: true,
                content: StatisticsView(store: store)
            )
            statisticsWindow?.contentMinSize = StatisticsLayout.minimumSize
        }
        present(statisticsWindow)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, resizable: Bool, content: Content) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func resizeSettings(to size: CGSize) {
        guard let window = settingsWindow, size.width > 0, size.height > 0 else { return }
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard window.contentView?.frame.size != size else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }
}
