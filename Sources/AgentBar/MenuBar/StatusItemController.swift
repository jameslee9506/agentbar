import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let store: AccountStore
    private let settings: AppSettings
    private let actions: PanelActions
    private let logger: StatusItemLogger?
    private var items: [StatusItemDescriptor.ID: NSStatusItem] = [:]
    private var order: [StatusItemDescriptor.ID] = []
    private var lastDescriptors: [StatusItemDescriptor.ID: StatusItemDescriptor] = [:]
    private let popover = NSPopover()
    private var presentedID: StatusItemDescriptor.ID?
    private var motionObserver: NSObjectProtocol?
    private var resetTask: Task<Void, Never>?
    private var running = false

    init(store: AccountStore, settings: AppSettings, actions: PanelActions, logger: StatusItemLogger? = nil) {
        self.store = store
        self.settings = settings
        self.actions = actions
        self.logger = logger
        super.init()
        popover.behavior = .transient
        popover.animates = false
    }

    func start() {
        running = true
        observe()
        // Reduce Motion decides whether marks move, so every item is drawn again when it changes.
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, running else { return }
                lastDescriptors.removeAll()
                update()
            }
        }
    }

    func stop() {
        running = false
        resetTask?.cancel()
        resetTask = nil
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        motionObserver = nil
        popover.close()
        items.values.forEach { NSStatusBar.system.removeStatusItem($0) }
        items.removeAll()
        order.removeAll()
    }

    func closePopover() { popover.close() }

    private func observe() {
        guard running else { return }
        withObservationTracking { update() } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    /// Draws the items as they are now, and again when a shown usage window resets: nothing that is
    /// observed changes then.
    private func update() {
        let now = Date.now
        reconcile(StatusItemPlan.make(accounts: store.accounts, settings: settings, now: now))
        resetTask?.cancel()
        resetTask = StatusItemPlan.nextReset(accounts: store.accounts, settings: settings, after: now).map { reset in
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(reset.timeIntervalSince(now)))
                guard !Task.isCancelled, let self, running else { return }
                update()
            }
        }
    }

    private func reconcile(_ descriptors: [StatusItemDescriptor]) {
        let newOrder = descriptors.map(\.id)
        if newOrder != order {
            popover.close()
            items.values.forEach { NSStatusBar.system.removeStatusItem($0) }
            items.removeAll()
            lastDescriptors.removeAll()
            // AppKit inserts new status items to the left of existing items.
            for descriptor in descriptors.reversed() {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(clicked(_:))
                items[descriptor.id] = item
            }
            order = newOrder
        }
        for descriptor in descriptors where lastDescriptors[descriptor.id] != descriptor {
            guard let button = items[descriptor.id]?.button else { continue }
            let moves = descriptor.workingCount > 0 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            button.image = StatusItemImage.make(descriptor, drawsMark: !moves)
            button.subviews.filter { $0 is StatusItemMotionView }.forEach { $0.removeFromSuperview() }
            if moves { StatusItemMotionView(provider: descriptor.provider).install(in: button) }
            button.imagePosition = .imageOnly
            button.toolTip = descriptor.accessibilityLabel
            button.setAccessibilityLabel(descriptor.accessibilityLabel)
            lastDescriptors[descriptor.id] = descriptor
        }
        logger?.record(descriptors)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let (id, _) = items.first(where: { $0.value.button === sender }) else { return }
        if popover.isShown && presentedID == id {
            popover.close()
            return
        }
        popover.close()
        presentedID = id
        let accountID = lastDescriptors[id]?.accountID
        let content = AccountPanelView(store: store, settings: settings, accountID: accountID, actions: actions)
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}
