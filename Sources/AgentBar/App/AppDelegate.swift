import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options: LaunchOptions
    private let store: AccountStore
    private let settings: AppSettings
    private let windows: WindowCoordinator
    private let scheduler: RefreshScheduler
    private let demoDefaultsName: String?
    private let statusLogger: StatusItemLogger?
    private var statusItems: StatusItemController?
    private var launchTask: Task<Void, Never>?

    init(options: LaunchOptions) {
        self.options = options
        statusLogger = options.log ? StatusItemLogger() : nil
        let defaultsName = options.demo ? "dev.agentbar.demo.\(UUID().uuidString)" : nil
        demoDefaultsName = defaultsName
        let defaults = defaultsName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        settings = AppSettings(defaults: defaults)
        store = AccountStore(providers: ProviderComposition.make(demo: options.demo))
        windows = WindowCoordinator(store: store, settings: settings, loginItem: LoginItemState(preview: options.demo))
        scheduler = RefreshScheduler(store: store, settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        if options.snapshotDirectory == nil {
            let actions = PanelActions(
                refresh: { [weak self] in
                    Task { @MainActor [weak self] in await self?.store.refresh(reason: .manual) }
                },
                statistics: { [weak self] in
                    self?.statusItems?.closePopover()
                    self?.windows.showStatistics()
                },
                settings: { [weak self] in self?.showSettings() },
                quit: { NSApp.terminate(nil) }
            )
            statusItems = StatusItemController(store: store, settings: settings, actions: actions, logger: statusLogger)
            statusItems?.start()
            scheduler.start()
        }
        launchTask = Task { [weak self] in
            guard let self else { return }
            await store.refresh(reason: .launch)
            if let directory = options.snapshotDirectory {
                do {
                    try await SnapshotExporter(store: store, settings: settings, logger: statusLogger).export(to: directory)
                    NSApp.terminate(nil)
                } catch {
                    FileHandle.standardError.write(Data("Snapshot export failed: \(error.localizedDescription)\n".utf8))
                    cleanUp()
                    exit(EXIT_FAILURE)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { cleanUp() }

    @objc private func showSettings() {
        statusItems?.closePopover()
        windows.showSettings()
    }

    private func cleanUp() {
        launchTask?.cancel()
        scheduler.stop()
        store.stop()
        statusItems?.stop()
        if let demoDefaultsName { UserDefaults.standard.removePersistentDomain(forName: demoDefaultsName) }
    }

    private func configureMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit AgentBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        NSApp.mainMenu = menu
    }
}
