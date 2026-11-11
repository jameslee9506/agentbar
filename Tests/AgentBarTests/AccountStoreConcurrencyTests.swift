@testable import AgentBar
import AgentBarCore
import Foundation
import Testing

@MainActor
struct AccountStoreConcurrencyTests {
    @Test func activityContinuesWhileCacheIsSuspendedAndReadsAreCoalesced() async {
        let a = TestFixtures.account("alpha")
        let b = TestFixtures.account("beta")
        let provider = TestProvider(kind: .claude, accounts: [a, b])
        let store = AccountStore(providers: [provider], now: { TestFixtures.date })
        defer { store.stop() }
        await store.refresh(reason: .launch)
        await store.waitForCacheHydration()
        let initialReads = provider.cacheCalls(for: a.id)
        let suspension = TestSuspension()
        defer { suspension.release() }
        provider.suspendCache(for: a.id, using: suspension)
        provider.emitActivity([a.id: TestFixtures.activity(.working), b.id: .none])
        #expect(await TestWait.until { suspension.isWaiting })
        #expect(store.states[a.id]?.activity.workingCount == 1)

        provider.setCache(TestFixtures.snapshot(62, at: TestFixtures.date.addingTimeInterval(1)), for: a.id)
        provider.emitActivity([a.id: TestFixtures.activity(.idle), b.id: TestFixtures.activity(.working)])
        #expect(await TestWait.until {
            store.states[a.id]?.activity.workingCount == 0 && store.states[b.id]?.activity.workingCount == 1
        })
        provider.emitActivity([a.id: TestFixtures.activity(.working), b.id: .none])
        #expect(await TestWait.until {
            store.states[a.id]?.activity.workingCount == 1 && store.states[b.id]?.activity.workingCount == 0
        })
        #expect(suspension.isWaiting)
        #expect(provider.cacheCalls(for: a.id) == initialReads + 1)
        suspension.release()
        await store.waitForCacheHydration()
        #expect(provider.cacheCalls(for: a.id) == initialReads + 2)
        #expect(store.states[a.id]?.usage?.windows.first?.usedPercent == 62)
    }

    @Test func liveUsageDoesNotWaitForAnotherAccountsCache() async {
        let a = TestFixtures.account("alpha")
        let b = TestFixtures.account("beta")
        let provider = TestProvider(kind: .claude, accounts: [a, b])
        provider.setResult(.success(TestFixtures.snapshot(18)), for: a.id)
        provider.setResult(.success(TestFixtures.snapshot(42)), for: b.id)
        let suspension = TestSuspension()
        defer { suspension.release() }
        provider.suspendCache(for: a.id, using: suspension)
        let store = AccountStore(providers: [provider], now: { TestFixtures.date })
        defer { store.stop() }
        let refresh = Task { await store.refresh(reason: .launch) }
        #expect(await TestWait.until { suspension.isWaiting })
        #expect(await TestWait.until {
            store.states[a.id]?.lastSuccessfulRefresh != nil && store.states[b.id]?.lastSuccessfulRefresh != nil
        })
        #expect(suspension.isWaiting)
        suspension.release()
        await refresh.value
    }

    @Test(arguments: [300.0, 120.0])
    func rateLimitSurvivesRemovalAndRediscovery(seconds: Double) async {
        let account = TestFixtures.account("alpha")
        let provider = TestProvider(kind: .claude, accounts: [account])
        let clock = TestClock()
        provider.setResult(.failure(.rateLimited(retryAfter: seconds == 300 ? nil : seconds)), for: account.id)
        let store = AccountStore(providers: [provider], now: { clock.date })
        defer { store.stop() }
        await store.refresh(reason: .launch)
        provider.setAccounts([])
        await store.refresh(reason: .manual)
        #expect(store.states[account.id] == nil)
        clock.advance(1)
        provider.setAccounts([account])
        provider.setResult(.success(TestFixtures.snapshot(12)), for: account.id)
        await store.refresh(reason: .manual)
        #expect(provider.calls(for: account.id) == 1)
        #expect(store.states[account.id]?.retryAfter == TestFixtures.date.addingTimeInterval(seconds))
        clock.advance(seconds - 2)
        await store.refresh(reason: .manual)
        #expect(provider.calls(for: account.id) == 1)
        clock.advance(1)
        await store.refresh(reason: .manual)
        #expect(provider.calls(for: account.id) == 2)
    }

    @Test func automaticThrottleSurvivesRemovalAndRediscovery() async {
        let account = TestFixtures.account("alpha")
        let provider = TestProvider(kind: .claude, accounts: [account])
        let clock = TestClock()
        let store = AccountStore(providers: [provider], now: { clock.date })
        defer { store.stop() }
        await store.refresh(reason: .launch)
        provider.setAccounts([])
        await store.refresh(reason: .timer)
        clock.advance(59)
        provider.setAccounts([account])
        await store.refresh(reason: .timer)
        #expect(provider.calls(for: account.id) == 1)
        #expect(store.states[account.id]?.lastAttempt == TestFixtures.date)
        clock.advance(1)
        await store.refresh(reason: .timer)
        #expect(provider.calls(for: account.id) == 2)
    }

    @Test func stopCancelsEveryLiveUsageRequest() async {
        let accounts = [TestFixtures.account("alpha"), TestFixtures.account("beta")]
        let provider = TestProvider(kind: .claude, accounts: accounts)
        let suspensions = accounts.map { _ in TestSuspension() }
        for (account, suspension) in zip(accounts, suspensions) {
            provider.suspendUsage(for: account.id, using: suspension)
        }
        let store = AccountStore(providers: [provider], now: { TestFixtures.date })
        defer { store.stop(); suspensions.forEach { $0.release() } }
        let refresh = Task { await store.refresh(reason: .launch) }
        #expect(await TestWait.until { suspensions.allSatisfy(\.isWaiting) })
        store.stop()
        #expect(await TestWait.until { accounts.allSatisfy { provider.cancelledCalls(for: $0.id) == 1 } })
        suspensions.forEach { $0.release() }
        await refresh.value
        #expect(!store.isRefreshing)
        #expect(store.accounts.allSatisfy { $0.usageError == nil })
    }

    @Test func removalCancelsOnlyThatAccountsRequestAndPreservesThrottle() async {
        let a = TestFixtures.account("alpha")
        let b = TestFixtures.account("beta")
        let provider = TestProvider(kind: .claude, accounts: [a, b])
        provider.setResult(.success(TestFixtures.snapshot(42)), for: b.id)
        let suspension = TestSuspension()
        defer { suspension.release() }
        provider.suspendUsage(for: a.id, using: suspension)
        let store = AccountStore(providers: [provider], now: { TestFixtures.date })
        defer { store.stop() }
        let refresh = Task { await store.refresh(reason: .launch) }
        #expect(await TestWait.until { suspension.isWaiting })
        provider.setAccounts([b])
        await store.refresh(reason: .timer)
        #expect(await TestWait.until { provider.cancelledCalls(for: a.id) == 1 })
        suspension.release()
        await refresh.value
        #expect(store.states[a.id] == nil)
        #expect(store.states[b.id]?.usage?.windows.first?.usedPercent == 42)
        #expect(provider.cancelledCalls(for: b.id) == 0)
        provider.setAccounts([a, b])
        await store.refresh(reason: .timer)
        #expect(provider.calls(for: a.id) == 1)
    }
}
