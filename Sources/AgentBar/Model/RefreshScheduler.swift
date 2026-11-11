import AppKit
import Observation

@MainActor
final class RefreshScheduler {
    private let store: AccountStore
    private let settings: AppSettings
    private var timerTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var running = false

    init(store: AccountStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func start() {
        running = true
        observeInterval()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.store.refresh(reason: .wake) }
        }
    }

    func stop() {
        running = false
        timerTask?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    private func observeInterval() {
        guard running else { return }
        let minutes = withObservationTracking {
            settings.refreshMinutes
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeInterval() }
        }
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(minutes * 60)) } catch { break }
                guard !Task.isCancelled, let self else { break }
                await store.refresh(reason: .timer)
            }
        }
    }
}
