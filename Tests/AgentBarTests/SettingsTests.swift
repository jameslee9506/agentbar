@testable import AgentBar
import Foundation
import Testing

@MainActor
struct SettingsTests {
    @Test func settingsPersistInAnIsolatedSuite() throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.menuBarMode == .separate)
        #expect(settings.showAccountNames)
        #expect(settings.menuBarNumber == .weeklyUsage)
        #expect(settings.refreshMinutes == 10)
        let id = TestFixtures.account("alpha").id
        settings.menuBarMode = .combined
        settings.showAccountNames = false
        settings.menuBarNumber = .workingSessions
        settings.refreshMinutes = 15
        settings.setVisible(false, for: id)
        let restored = AppSettings(defaults: defaults)
        #expect(restored.menuBarMode == .combined)
        #expect(!restored.showAccountNames)
        #expect(restored.menuBarNumber == .workingSessions)
        #expect(restored.refreshMinutes == 15)
        #expect(!restored.isVisible(id))
        restored.setVisible(true, for: id)
        #expect(AppSettings(defaults: defaults).isVisible(id))
    }

    @Test func accountOrderPersistsAndKeepsAccountsThatAreGone() throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let a = TestFixtures.account("alpha").id
        let b = TestFixtures.account("beta").id
        let c = TestFixtures.account("gamma", kind: .codex).id
        #expect(settings.accountOrder.isEmpty)
        settings.setAccountOrder([c, a, b])
        #expect(AppSettings(defaults: defaults).accountOrder == [c, a, b].map(\.description))
        // Arranged while gamma is gone: it stays ordered, after the accounts arranged.
        settings.setAccountOrder([b, a])
        #expect(AppSettings(defaults: defaults).accountOrder == [b, a, c].map(\.description))
    }

    @Test func invalidStoredValuesFallBackToDefaults() throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: "menuBarMode")
        defaults.set("unknown", forKey: "menuBarNumber")
        defaults.set(-20, forKey: "refreshMinutes")
        defaults.set(42, forKey: "accountOrder")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.menuBarMode == .separate)
        #expect(settings.menuBarNumber == .weeklyUsage)
        #expect(settings.refreshMinutes == 10)
        #expect(settings.accountOrder.isEmpty)
        settings.refreshMinutes = 0
        #expect(settings.refreshMinutes == 10)
        #expect(defaults.integer(forKey: "refreshMinutes") == 10)
        // The 2-minute interval is no longer offered.
        defaults.set(2, forKey: "refreshMinutes")
        #expect(AppSettings(defaults: defaults).refreshMinutes == 10)
    }
}
