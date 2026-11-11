/// The number a menu bar item shows after its mark and name.
enum MenuBarNumber: String, CaseIterable, Identifiable {
    case workingSessions
    case weeklyUsage
    case off

    var id: Self { self }
    var title: String {
        switch self {
        case .workingSessions: "Working sessions"
        case .weeklyUsage: "Weekly usage"
        case .off: "Off"
        }
    }
}
