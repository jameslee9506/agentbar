import AgentBarCore
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let refreshIntervals = [2, 5, 15, 30]

    var menuBarMode: MenuBarMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: "menuBarMode") }
    }
    var showAccountNames: Bool {
        didSet { defaults.set(showAccountNames, forKey: "showAccountNames") }
    }
    var refreshMinutes: Int {
        didSet {
            if !Self.refreshIntervals.contains(refreshMinutes) { refreshMinutes = 5 }
            defaults.set(refreshMinutes, forKey: "refreshMinutes")
        }
    }
    private(set) var hiddenAccountIDs: Set<String> {
        didSet { defaults.set(hiddenAccountIDs.sorted(), forKey: "hiddenAccountIDs") }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarMode = MenuBarMode(rawValue: defaults.string(forKey: "menuBarMode") ?? "") ?? .separate
        showAccountNames = defaults.object(forKey: "showAccountNames") as? Bool ?? true
        let interval = defaults.integer(forKey: "refreshMinutes")
        refreshMinutes = Self.refreshIntervals.contains(interval) ? interval : 5
        hiddenAccountIDs = Set(defaults.stringArray(forKey: "hiddenAccountIDs") ?? [])
    }

    func isVisible(_ id: AccountID) -> Bool { !hiddenAccountIDs.contains(id.description) }

    func setVisible(_ visible: Bool, for id: AccountID) {
        if visible {
            hiddenAccountIDs.remove(id.description)
        } else {
            hiddenAccountIDs.insert(id.description)
        }
    }
}
