import AgentBarCore
import Foundation

final class TestProvider: AccountProvider, @unchecked Sendable {
    let kind: ProviderKind
    private let lock = NSLock()
    private var accountList: [Account]
    private var cached: [AccountID: UsageSnapshot] = [:]
    private var results: [AccountID: Result<UsageSnapshot, UsageError>] = [:]
    private var history: [AccountID: UsageStatistics] = [:]
    private var counts: [AccountID: Int] = [:]
    private var cacheCounts: [AccountID: Int] = [:]
    private var cancellations: [AccountID: Int] = [:]
    private var cacheSuspensions: [AccountID: TestSuspension] = [:]
    private var usageSuspensions: [AccountID: TestSuspension] = [:]
    private var discoveries = 0
    private var streams = 0
    private var continuation: AsyncStream<[AccountID: AccountActivity]>.Continuation?
    private var delay: Duration = .zero

    init(kind: ProviderKind, accounts: [Account]) {
        self.kind = kind
        accountList = accounts
    }

    func accounts() async -> [Account] {
        lock.withLock {
            discoveries += 1
            return accountList
        }
    }

    func cachedUsage(for account: Account) async -> UsageSnapshot? {
        let (snapshot, suspension) = lock.withLock {
            cacheCounts[account.id, default: 0] += 1
            return (cached[account.id], cacheSuspensions[account.id])
        }
        await suspension?.wait()
        return snapshot
    }

    func usage(for account: Account) async throws(UsageError) -> UsageSnapshot {
        let (result, delay, suspension) = lock.withLock {
            counts[account.id, default: 0] += 1
            return (results[account.id] ?? .failure(.signedOut), delay, usageSuspensions[account.id])
        }
        await suspension?.wait()
        try? await Task.sleep(for: delay)
        if Task.isCancelled {
            lock.withLock { cancellations[account.id, default: 0] += 1 }
            throw .unavailable("Cancelled")
        }
        return try result.get()
    }

    func activity(for accounts: [Account]) -> AsyncStream<[AccountID: AccountActivity]> {
        AsyncStream { continuation in
            lock.withLock {
                streams += 1
                self.continuation?.finish()
                self.continuation = continuation
            }
            continuation.yield(Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, .none) }))
        }
    }

    func statistics(for account: Account, days: Int) async -> UsageStatistics {
        lock.withLock { history[account.id] ?? .empty }
    }

    func setAccounts(_ accounts: [Account]) { lock.withLock { accountList = accounts } }
    func setCache(_ snapshot: UsageSnapshot, for id: AccountID) { lock.withLock { cached[id] = snapshot } }
    func setResult(_ result: Result<UsageSnapshot, UsageError>, for id: AccountID) { lock.withLock { results[id] = result } }
    func setStatistics(_ statistics: UsageStatistics, for id: AccountID) { lock.withLock { history[id] = statistics } }
    func setDelay(_ delay: Duration) { lock.withLock { self.delay = delay } }
    func suspendCache(for id: AccountID, using suspension: TestSuspension) {
        lock.withLock { cacheSuspensions[id] = suspension }
    }
    func suspendUsage(for id: AccountID, using suspension: TestSuspension) {
        lock.withLock { usageSuspensions[id] = suspension }
    }
    func emitActivity(_ activity: [AccountID: AccountActivity]) {
        let sink = lock.withLock { continuation }
        sink?.yield(activity)
    }
    func calls(for id: AccountID) -> Int { lock.withLock { counts[id, default: 0] } }
    func cacheCalls(for id: AccountID) -> Int { lock.withLock { cacheCounts[id, default: 0] } }
    func cancelledCalls(for id: AccountID) -> Int { lock.withLock { cancellations[id, default: 0] } }
    var discoveryCount: Int { lock.withLock { discoveries } }
    var streamCount: Int { lock.withLock { streams } }
}
