import Foundation

final class TestSuspension: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var isWaiting: Bool { lock.withLock { !continuations.isEmpty } }

    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resume = lock.withLock {
                    if released { return true }
                    continuations.append(continuation)
                    return false
                }
                if resume { continuation.resume() }
            }
        } onCancel: {
            self.release()
        }
    }

    func release() {
        let pending = lock.withLock {
            released = true
            let pending = continuations
            continuations.removeAll()
            return pending
        }
        pending.forEach { $0.resume() }
    }
}
