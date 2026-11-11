@MainActor
struct PanelActions {
    var refresh: () -> Void
    var statistics: () -> Void
    var settings: () -> Void
    var quit: () -> Void

    static let none = PanelActions(refresh: {}, statistics: {}, settings: {}, quit: {})
}
