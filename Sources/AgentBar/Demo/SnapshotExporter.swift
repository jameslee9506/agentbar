import AppKit
import SwiftUI

@MainActor
struct SnapshotExporter {
    let store: AccountStore
    let settings: AppSettings
    let logger: StatusItemLogger?

    func export(to directory: URL) async throws {
        await store.waitForCacheHydration()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = (settings.menuBarMode, settings.menuBarNumber)
        defer { (settings.menuBarMode, settings.menuBarNumber) = original }
        var settingsCases: [(count: Int, store: AccountStore)] = []
        for count in [4, 30] {
            let caseStore = AccountStore(providers: [
                DemoProvider(kind: .claude, accountCount: count / 2),
                DemoProvider(kind: .codex, accountCount: count / 2),
            ])
            await caseStore.refresh(reason: .launch)
            settingsCases.append((count, caseStore))
        }
        defer { settingsCases.forEach { $0.store.stop() } }
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            for mode in MenuBarMode.allCases {
                for number in MenuBarNumber.allCases {
                    (settings.menuBarMode, settings.menuBarNumber) = (mode, number)
                    let descriptors = StatusItemPlan.make(accounts: store.accounts, settings: settings, now: .now)
                    logger?.record(descriptors)
                    try await render(
                        StatusSnapshotView(descriptors: descriptors), size: nil, dark: dark,
                        to: directory.appendingPathComponent("status-\(mode.rawValue)-\(number.rawValue)-\(suffix).png")
                    )
                }
            }
            (settings.menuBarMode, settings.menuBarNumber) = (.separate, .weeklyUsage)
            try await render(
                AccountPanelView(store: store, settings: settings, accountID: store.accounts.first?.id, actions: .none),
                size: nil, dark: dark, to: directory.appendingPathComponent("panel-account-\(suffix).png")
            )
            try await render(
                AccountPanelView(store: store, settings: settings, accountID: nil, actions: .none),
                size: nil, dark: dark, to: directory.appendingPathComponent("panel-all-\(suffix).png")
            )
            for tab in [SettingsTab.general, .accounts] {
                try await render(
                    SettingsView(store: store, settings: settings, loginItem: LoginItemState(preview: true), selection: tab),
                    size: nil, dark: dark,
                    to: directory.appendingPathComponent("settings-\(tab == .general ? "general" : "accounts")-\(suffix).png")
                )
                for settingsCase in settingsCases {
                    try await render(
                        SettingsView(store: settingsCase.store, settings: settings, loginItem: LoginItemState(preview: true), selection: tab),
                        size: nil, dark: dark,
                        to: directory.appendingPathComponent("settings-\(tab == .general ? "general" : "accounts")-\(settingsCase.count)-\(suffix).png")
                    )
                }
            }
            // The second account dragged down past the third.
            let dragged = MenuBarAccounts.ordered(store.accounts, settings: settings).dropFirst().first
            try await render(
                AccountSettingsView(
                    store: store, settings: settings,
                    drag: dragged.map { AccountSettingsView.Drag(id: $0.id, grab: 28, pointer: 150) }
                )
                .frame(width: 460).padding(.vertical, 16).background(.background),
                // Rows make room once they have been measured.
                size: nil, dark: dark, settle: .milliseconds(500),
                to: directory.appendingPathComponent("settings-accounts-dragging-\(suffix).png")
            )
            try await render(
                StatisticsView(store: store), size: StatisticsLayout.preferredSize, dark: dark,
                to: directory.appendingPathComponent("statistics-accounts-\(suffix).png")
            )
            try await render(
                StatisticsView(store: store, selectedAccount: store.accounts.first?.id, days: 30),
                size: StatisticsLayout.preferredSize, dark: dark,
                to: directory.appendingPathComponent("statistics-models-\(suffix).png")
            )
            try await render(
                StatisticsView(store: store), size: StatisticsLayout.minimumSize, dark: dark,
                to: directory.appendingPathComponent("statistics-minimum-\(suffix).png")
            )
        }
    }

    /// `settle` is how long the view takes to measure itself and finish moving.
    private func render<Content: View>(
        _ content: Content, size: NSSize?, dark: Bool, settle: Duration = .milliseconds(100), to url: URL
    ) async throws {
        let view = NSHostingView(rootView: content
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.showsWorkingMotion, false))
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.appearance = appearance
        var fitting = size ?? view.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { throw CocoaError(.fileWriteUnknown) }
        var bounds = NSRect(origin: .zero, size: fitting)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = view
        view.frame = bounds
        view.layoutSubtreeIfNeeded()
        // Let SwiftUI resolve native controls without ever presenting the window.
        try await Task.sleep(for: settle)
        view.layoutSubtreeIfNeeded()
        if size == nil {
            fitting = view.fittingSize
            bounds = NSRect(origin: .zero, size: fitting)
            window.setContentSize(fitting)
            view.frame = bounds
            view.layoutSubtreeIfNeeded()
        }
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(fitting.width * 2), pixelsHigh: Int(fitting.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        bitmap.size = fitting
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        window.close()
    }
}
