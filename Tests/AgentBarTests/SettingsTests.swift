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
        #expect(settings.refreshMinutes == 5)
        let id = TestFixtures.account("alpha").id
        settings.menuBarMode = .combined
        settings.showAccountNames = false
        settings.refreshMinutes = 15
        settings.setVisible(false, for: id)
        let restored = AppSettings(defaults: defaults)
        #expect(restored.menuBarMode == .combined)
        #expect(!restored.showAccountNames)
        #expect(restored.refreshMinutes == 15)
        #expect(!restored.isVisible(id))
        restored.setVisible(true, for: id)
        #expect(AppSettings(defaults: defaults).isVisible(id))
    }

    @Test func invalidStoredValuesFallBackToDefaults() throws {
        let suite = "dev.agentbar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: "menuBarMode")
        defaults.set(-20, forKey: "refreshMinutes")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.menuBarMode == .separate)
        #expect(settings.refreshMinutes == 5)
        settings.refreshMinutes = 0
        #expect(settings.refreshMinutes == 5)
        #expect(defaults.integer(forKey: "refreshMinutes") == 5)
    }
}
