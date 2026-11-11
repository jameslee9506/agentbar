enum RefreshReason: Sendable {
    case launch
    case timer
    case manual
    case wake
    case workEnded

    var discoversAccounts: Bool {
        switch self {
        case .launch, .timer, .manual: true
        case .wake, .workEnded: false
        }
    }
}
