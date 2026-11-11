@testable import AgentBar
import AgentBarCore
import Foundation
import Testing

@MainActor
struct AccountStoreTests {
    @Test func failuresAreIsolatedAndCachedUsageRemainsVisible() async throws {
        let a = TestFixtures.account("alpha")
        let b = TestFixtures.account("beta", kind: .codex)
        let claude = TestProvider(kind: .claude, accounts: [a])
        let codex = TestProvider(kind: .codex, accounts: [b])
        claude.setCache(TestFixtures.snapshot(82), for: a.id)
        claude.setResult(.failure(.sessionExpired), for: a.id)
        codex.setResult(.success(TestFixtures.snapshot(23)), for: b.id)
        codex.setStatistics(UsageStatistics(days: [DailyUsage(day: TestFixtures.date, byModel: ["test-model": TokenCount(input: 12)])]), for: b.id)
        let store = AccountStore(providers: [claude, codex], now: { TestFixtures.date })
        defer { store.stop() }
        await store.refresh(reason: .launch)
        await store.waitForCacheHydration()
        let failed = try #require(store.states[a.id])
        let success = try #require(store.states[b.id])
        #expect(failed.usage?.windows.first?.usedPercent == 82)
        #expect(failed.usageError == .sessionExpired)
        #expect(failed.isStale)
        #expect(failed.lastSuccessfulRefresh == nil)
        #expect(success.usage?.windows.first?.usedPercent == 23)
        #expect(success.usageError == nil)
        #expect(success.lastSuccessfulRefresh == TestFixtures.date)
        #expect(success.statistics.total.input == 12)
        #expect(!success.isStale)
    }

    @Test func failedRefreshKeepsLiveSnapshotAndRollsExpiredWindowForward() async throws {
        let account = TestFixtures.account("alpha")
        let provider = TestProvider(kind: .claude, accounts: [account])
        let clock = TestClock()
        provider.setResult(.success(TestFixtures.snapshot(90, reset: clock.date.addingTimeInterval(20))), for: account.id)
        let store = AccountStore(providers: [provider], now: { clock.date })
        defer { store.stop() }
        await store.refresh(reason: .launch)
        provider.setCache(TestFixtures.snapshot(10, at: clock.date.addingTimeInterval(-60)), for: account.id)
        provider.setResult(.failure(.unavailable("Offline")), for: account.id)
        clock.advance(30)
        await store.refresh(reason: .manual)
        let state = try #require(store.states[account.id])
        #expect(state.usage?.windows.first?.usedPercent == 90)
        #expect(state.snapshot(at: clock.date)?.windows.first?.usedPercent == 0)
        #expect(state.isStale)
        #expect(state.lastSuccessfulRefresh == TestFixtures.date)
    }

    @Test func automaticRefreshIsThrottledButManualRefreshIsAllowed() async {
        let account = TestFixtures.account("alpha")
        let provider = TestProvider(kind: .claude, accounts: [account])
        let clock = TestClock()
        provider.setResult(.success(TestFixtures.snapshot(12)), for: account.id)
        let store = AccountStore(providers: [provider], now: { clock.date })
        defer { store.stop() }
        await store.refresh(reason: .launch)
        clock.advance(59)
        await store.refresh(reason: .timer)
        await store.refresh(reason: .wake)
        #expect(provider.calls(for: account.id) == 1)
        #expect(provider.discoveryCount == 2)
        await store.refresh(reason: .manual)
        #expect(provider.calls(for: account.id) == 2)
        clock.advance(60)
        await store.refresh(reason: .timer)
        #expect(provider.calls(for: account.id) == 3)
    }

    @Test(arguments: [300.0, 120.0])
    func rateLimitsBlockManualRefreshUntilRetryTime(seconds: Double) async {
        let account = TestFixtures.account("alpha")
        let provider = TestProvider(kind: .claude, accounts: [account])
        let clock = TestClock()
        provider.setResult(.failure(.rateLimited(retryAfter: seconds == 300 ? nil : seconds)), for: account.id)
        let store = AccountStore(providers: [provider], now: { clock.date })
        defer { store.stop() }
        await store.refresh(reason: .launch)
        clock.advance(seconds - 1)
        await store.refresh(reason: .manual)
        #expect(provider.calls(for: account.id) == 1)
        provider.setResult(.success(TestFixtures.snapshot(18)), for: account.id)
        clock.advance(1)
        await store.refresh(reason: .manual)
        #expect(provider.calls(for: account.id) == 2)
        #expect(store.states[account.id]?.usageError == nil)
        #expect(store.states[account.id]?.retryAfter == nil)
    }

    @Test func activityReadsFreshLocalUsageAndWorkEndRefreshes() async {
        let account = TestFixtures.account("alpha")
        let provider = TestProvider(kind: .claude, accounts: [account])
        let clock = TestClock()
        provider.setResult(.success(TestFixtures.snapshot(18)), for: account.id)
        let store = AccountStore(providers: [provider], now: { clock.date }, workEndDelay: 0)
        defer { store.stop() }
        await store.refresh(reason: .launch)
        clock.advance(61)
        provider.setCache(TestFixtures.snapshot(45, at: clock.date), for: account.id)
        store.applyActivity([account.id: TestFixtures.activity(.working)], kind: .claude)
        await store.waitForCacheHydration()
        #expect(store.states[account.id]?.usage?.windows.first?.usedPercent == 45)
        #expect(store.workingCount == 1)
        store.applyActivity([account.id: TestFixtures.activity(.idle)], kind: .claude)
        await store.waitForWorkEndRefreshes()
        #expect(provider.calls(for: account.id) == 2)
        #expect(store.workingCount == 0)
        #expect(store.states[account.id]?.usage?.windows.first?.usedPercent == 45)
        store.applyActivity([account.id: TestFixtures.activity(.idle)], kind: .claude)
        #expect(provider.calls(for: account.id) == 2)
    }

    @Test func rediscoveryAddsAndRemovesAccountsAndRestartsActivity() async {
        let a = TestFixtures.account("alpha")
        let b = TestFixtures.account("beta")
        let provider = TestProvider(kind: .claude, accounts: [a])
        let store = AccountStore(providers: [provider], now: { TestFixtures.date })
        defer { store.stop() }
        await store.refresh(reason: .launch)
        #expect(provider.streamCount == 1)
        await store.refresh(reason: .manual)
        #expect(provider.streamCount == 1)
        provider.setAccounts([a, b])
        await store.refresh(reason: .timer)
        #expect(store.accounts.map(\.id) == [a.id, b.id])
        #expect(provider.streamCount == 2)
        #expect(provider.calls(for: b.id) == 1)
        provider.setAccounts([b])
        await store.refresh(reason: .manual)
        #expect(store.states[a.id] == nil)
        #expect(store.accounts.map(\.id) == [b.id])
        #expect(provider.streamCount == 3)
    }

    @Test func simultaneousRefreshesDoNotDuplicateInFlightRequests() async {
        let account = TestFixtures.account("alpha")
        let provider = TestProvider(kind: .claude, accounts: [account])
        let store = AccountStore(providers: [provider], now: { TestFixtures.date })
        defer { store.stop() }
        await store.refresh(reason: .launch)
        provider.setDelay(.milliseconds(20))
        async let first: Void = store.refreshUsage(for: [account.id], reason: .manual)
        async let second: Void = store.refreshUsage(for: [account.id], reason: .manual)
        _ = await (first, second)
        #expect(provider.calls(for: account.id) == 2)
    }

    @Test func automaticRefreshDateRespectsWorkEndCooldownAndRateLimit() {
        var state = AccountState(account: TestFixtures.account("alpha"))
        state.lastAttempt = TestFixtures.date
        #expect(state.nextAutomaticRefresh(at: TestFixtures.date.addingTimeInterval(3)) == TestFixtures.date.addingTimeInterval(60))
        state.retryAfter = TestFixtures.date.addingTimeInterval(300)
        #expect(state.nextAutomaticRefresh(at: TestFixtures.date.addingTimeInterval(3)) == TestFixtures.date.addingTimeInterval(300))
        #expect(!state.canRefresh(at: TestFixtures.date, manually: true))
    }
}
