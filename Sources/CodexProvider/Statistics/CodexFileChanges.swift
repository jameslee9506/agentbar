import AgentBarCore
import Foundation

final class CodexFileChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []
    private let watcher: DirectoryWatcher?
    private var task: Task<Void, Never>?

    init(home: URL) {
        watcher = try? DirectoryWatcher(directories: [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")])
        if let events = watcher?.events {
            task = Task { [weak self] in
                for await changes in events {
                    guard !Task.isCancelled else { break }
                    self?.add(changes)
                }
            }
        }
    }

    deinit { task?.cancel(); watcher?.stop() }

    func take() -> Set<String> {
        lock.withLock {
            let current = paths
            paths.removeAll(keepingCapacity: true)
            return current
        }
    }

    private func add(_ changes: [String]) { lock.withLock { paths.formUnion(changes) } }
}
