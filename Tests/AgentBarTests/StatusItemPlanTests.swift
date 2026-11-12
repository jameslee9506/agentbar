@testable import AgentBar
import AgentBarCore
import Foundation
import Testing

@MainActor
struct StatusItemPlanTests {
    @Test func separateItemsAreSortedAndRespectVisibilityAndNames() throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let a = TestFixtures.account("alpha")
        let b = TestFixtures.account("beta")
        let c = TestFixtures.account("alpha", kind: .codex)
        let accounts = [c, b, a].map { AccountState(account: $0) }
        let plan = StatusItemPlan.make(accounts: accounts, settings: settings, now: TestFixtures.date)
        #expect(plan.map(\.accountID) == [a.id, b.id, c.id])
        #expect(plan.map(\.name) == ["alpha", "beta", "alpha"])
        settings.setVisible(false, for: b.id)
        settings.showAccountNames = false
        let hidden = StatusItemPlan.make(accounts: accounts, settings: settings, now: TestFixtures.date)
        #expect(hidden.map(\.accountID) == [a.id, c.id])
        #expect(hidden.allSatisfy { $0.name == nil })
        settings.setVisible(false, for: a.id)
        settings.setVisible(false, for: c.id)
        #expect(StatusItemPlan.make(accounts: accounts, settings: settings, now: TestFixtures.date).map(\.id) == [.overview])
    }

    @Test func itemsAndPanelFollowTheOrderArrangedInSettings() async throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let a = TestFixtures.account("alpha")
        let b = TestFixtures.account("beta")
        let c = TestFixtures.account("gamma", kind: .codex)
        let d = TestFixtures.account("delta")
        let accounts = [c, d, b, a].map { AccountState(account: $0) }
        func plan() -> [AccountID?] {
            StatusItemPlan.make(accounts: accounts, settings: settings, now: TestFixtures.date).map(\.accountID)
        }
        #expect(plan() == [a.id, b.id, d.id, c.id])
        settings.setAccountOrder([c.id, b.id])
        // Accounts never arranged follow, in their default order.
        #expect(plan() == [c.id, b.id, a.id, d.id])
        settings.setVisible(false, for: c.id)
        #expect(plan() == [b.id, a.id, d.id])
        #expect(MenuBarAccounts.ordered(accounts, settings: settings).map(\.id) == [c.id, b.id, a.id, d.id])

        settings.menuBarMode = .combined
        let store = AccountStore(providers: [
            TestProvider(kind: .claude, accounts: [a, b, d]), TestProvider(kind: .codex, accounts: [c]),
        ])
        defer { store.stop() }
        await store.refresh(reason: .launch)
        let panel = AccountPanelView(store: store, settings: settings, accountID: nil, actions: .none)
        #expect(panel.accounts.map(\.id) == [b.id, a.id, d.id])
    }

    @Test func combinedExcludesHiddenWorkingSessions() throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.menuBarMode = .combined
        var a = AccountState(account: TestFixtures.account("alpha"))
        a.activity = TestFixtures.activity(.working)
        settings.setVisible(false, for: a.id)
        let plan = StatusItemPlan.make(accounts: [a], settings: settings, now: TestFixtures.date)
        #expect(plan.count == 1)
        #expect(plan.first?.id == .overview)
        #expect(plan.first?.workingCount == 0)
    }

    @Test func combinedPanelAndCountUseTheSameVisibleAccounts() async throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.menuBarMode = .combined
        let a = TestFixtures.account("alpha")
        let b = TestFixtures.account("beta")
        let store = AccountStore(providers: [TestProvider(kind: .claude, accounts: [a, b])])
        defer { store.stop() }
        await store.refresh(reason: .launch)
        store.applyActivity([a.id: TestFixtures.activity(.working), b.id: TestFixtures.activity(.working)], kind: .claude)
        settings.setVisible(false, for: a.id)
        let panel = AccountPanelView(store: store, settings: settings, accountID: nil, actions: .none)
        #expect(panel.accounts.map(\.id) == [b.id])
        #expect(StatusItemPlan.make(accounts: store.accounts, settings: settings, now: TestFixtures.date).first?.workingCount == 1)
        #expect(AccountPanelView(store: store, settings: settings, accountID: a.id, actions: .none).accounts.isEmpty)
        #expect(store.accounts.count == 2)
        #expect(StatisticsReport(accounts: store.accounts, selectedAccount: nil, days: 7, now: TestFixtures.date).rows.count == 2)
        settings.setVisible(false, for: b.id)
        #expect(panel.accounts.isEmpty)
        #expect(StatusItemPlan.make(accounts: store.accounts, settings: settings, now: TestFixtures.date).first?.workingCount == 0)
        settings.menuBarMode = .separate
        #expect(StatusItemPlan.make(accounts: store.accounts, settings: settings, now: TestFixtures.date).first?.workingCount == 0)
    }

    @Test func numberIsTheWorkingCountTheWeeklyUsageOrNothing() throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let reset = TestFixtures.date.addingTimeInterval(60)
        var a = state("alpha", weekly: 67.5, reset: reset)
        a.activity = TestFixtures.activity(.working)
        let b = state("beta", weekly: nil)
        func plan(at date: Date = TestFixtures.date) -> [StatusItemDescriptor] {
            StatusItemPlan.make(accounts: [a, b], settings: settings, now: date)
        }
        settings.menuBarNumber = .workingSessions
        #expect(plan().map(\.displayedNumber) == ["1", nil])
        #expect(plan().map(\.accessibilityLabel) == ["Claude Code, alpha, 1 working", "Claude Code, beta"])
        // Usage that is not shown does not change an item, so the item is not drawn again.
        #expect(plan(at: reset) == plan())

        settings.menuBarNumber = .weeklyUsage
        #expect(plan().map(\.displayedNumber) == ["68%", nil])
        #expect(plan().map(\.workingCount) == [1, 0])
        #expect(plan().map(\.accessibilityLabel) == ["Claude Code, alpha, 1 working, weekly usage 68%", "Claude Code, beta"])
        // A window that has reset is empty, as in the panel.
        #expect(plan(at: reset).map(\.displayedNumber) == ["0%", nil])

        settings.menuBarNumber = .off
        #expect(plan().map(\.displayedNumber) == [nil, nil])
        #expect(plan().map(\.workingCount) == [1, 0])
        #expect(plan().map(\.accessibilityLabel) == ["Claude Code, alpha, 1 working", "Claude Code, beta"])
        #expect(plan(at: reset) == plan())
    }

    @Test func combinedItemShowsTheHighestWeeklyUsageOfVisibleAccounts() throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.menuBarMode = .combined
        settings.menuBarNumber = .weeklyUsage
        let a = state("alpha", weekly: 40)
        let b = state("beta", weekly: 87)
        let c = state("gamma", kind: .codex, weekly: nil)
        func item() -> StatusItemDescriptor? {
            StatusItemPlan.make(accounts: [a, b, c], settings: settings, now: TestFixtures.date).first
        }
        #expect(item()?.displayedNumber == "87%")
        #expect(item()?.accessibilityLabel == "AgentBar, weekly usage up to 87%")
        settings.setVisible(false, for: b.id)
        #expect(item()?.displayedNumber == "40%")
        settings.setVisible(false, for: a.id)
        #expect(item()?.displayedNumber == nil)
        #expect(item()?.accessibilityLabel == "AgentBar")
    }

    @Test func nextResetIsTheEarliestAheadAmongShownWeeklyWindows() throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let date = TestFixtures.date
        let accounts = [
            state("alpha", weekly: 40, reset: date.addingTimeInterval(300)),
            state("beta", weekly: 87, reset: date.addingTimeInterval(100)),
            state("gamma", weekly: 12, reset: date),
            state("delta", weekly: 5),
            AccountState(account: TestFixtures.account("epsilon")),
        ]
        func next(after now: Date = date) -> Date? {
            StatusItemPlan.nextReset(accounts: accounts, settings: settings, after: now)
        }
        // A count never changes by itself.
        settings.menuBarNumber = .workingSessions
        #expect(next() == nil)
        settings.menuBarNumber = .weeklyUsage
        #expect(next() == date.addingTimeInterval(100))
        settings.setVisible(false, for: accounts[1].id)
        #expect(next() == date.addingTimeInterval(300))
        settings.menuBarMode = .combined
        #expect(next() == date.addingTimeInterval(300))
        #expect(next(after: date.addingTimeInterval(300)) == nil)
    }

    /// An account with a session window, a weekly window of one model, and the weekly window if `weekly`
    /// is given. Only the last one counts, though the others are fuller and reset sooner.
    private func state(_ name: String, kind: ProviderKind = .claude, weekly: Double?, reset: Date? = nil) -> AccountState {
        var state = AccountState(account: TestFixtures.account(name, kind: kind))
        let soon = TestFixtures.date.addingTimeInterval(10)
        state.usage = UsageSnapshot(windows: [
            UsageWindow(id: "session", title: "5h", usedPercent: 99, resetsAt: soon),
            weekly.map { UsageWindow(id: "weekly", title: "Week", usedPercent: $0, resetsAt: reset) },
            UsageWindow(id: "weekly.opus", title: "Opus", usedPercent: 98, resetsAt: soon),
        ].compactMap { $0 }, capturedAt: TestFixtures.date)
        return state
    }
}
