import Foundation

actor CodexStatisticsScheduler {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func run<Result: Sendable>(_ operation: @Sendable () async -> Result) async -> Result {
        if busy { await withCheckedContinuation { waiting.append($0) } }
        else { busy = true }
        let result = await operation()
        if waiting.isEmpty { busy = false }
        else { waiting.removeFirst().resume() }
        return result
    }
}
