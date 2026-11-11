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
        let plan = StatusItemPlan.make(accounts: accounts, settings: settings)
        #expect(plan.map(\.accountID) == [a.id, b.id, c.id])
        #expect(plan.map(\.name) == ["alpha", "beta", "alpha"])
        settings.setVisible(false, for: b.id)
        settings.showAccountNames = false
        let hidden = StatusItemPlan.make(accounts: accounts, settings: settings)
        #expect(hidden.map(\.accountID) == [a.id, c.id])
        #expect(hidden.allSatisfy { $0.name == nil })
        settings.setVisible(false, for: a.id)
        settings.setVisible(false, for: c.id)
        #expect(StatusItemPlan.make(accounts: accounts, settings: settings).map(\.id) == [.overview])
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
        let plan = StatusItemPlan.make(accounts: [a], settings: settings)
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
        #expect(StatusItemPlan.make(accounts: store.accounts, settings: settings).first?.workingCount == 1)
        #expect(AccountPanelView(store: store, settings: settings, accountID: a.id, actions: .none).accounts.isEmpty)
        #expect(store.accounts.count == 2)
        #expect(StatisticsReport(accounts: store.accounts, selectedAccount: nil, days: 7, now: TestFixtures.date).rows.count == 2)
        settings.setVisible(false, for: b.id)
        #expect(panel.accounts.isEmpty)
        #expect(StatusItemPlan.make(accounts: store.accounts, settings: settings).first?.workingCount == 0)
        settings.menuBarMode = .separate
        #expect(StatusItemPlan.make(accounts: store.accounts, settings: settings).first?.workingCount == 0)
    }
}
