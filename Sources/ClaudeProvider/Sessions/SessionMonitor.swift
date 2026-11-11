import AgentBarCore
import Foundation

struct SessionMonitor: Sendable {
    let root: URL
    let processes: any ProcessListing
    let pollInterval: Duration

    func activity(for accounts: [Account]) -> AsyncStream<[AccountID: AccountActivity]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task.detached(priority: .utility) {
                guard !accounts.isEmpty else {
                    continuation.yield([:])
                    continuation.finish()
                    return
                }
                let watcher = try? DirectoryWatcher(directories: accounts.map { $0.home.appendingPathComponent("sessions") })
                let (changes, trigger) = AsyncStream<Bool>.makeStream(bufferingPolicy: .unbounded)
                let fileTask = Task {
                    guard let watcher else { return }
                    for await _ in watcher.events {
                        if Task.isCancelled { break }
                        trigger.yield(false)
                    }
                }
                let pollTask = Task {
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: pollInterval) } catch { break }
                        trigger.yield(true)
                    }
                }
                defer {
                    fileTask.cancel()
                    pollTask.cancel()
                    watcher?.stop()
                    trigger.finish()
                    continuation.finish()
                }
                var scanner = SessionScanner(root: root, processes: processes)
                var previous: [AccountID: AccountActivity]?
                trigger.yield(true)
                for await refreshProcesses in changes {
                    if Task.isCancelled { break }
                    let current = scanner.snapshot(accounts: accounts, refreshProcesses: refreshProcesses)
                    if current != previous {
                        previous = current
                        continuation.yield(current)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
