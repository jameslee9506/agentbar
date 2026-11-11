import SwiftUI

/// The motion of a mark whose account is working. Every view derives it from the clock, so marks of
/// the same account move together.
enum WorkingMotion {
    /// Seconds per cycle: one turn of a provider mark.
    static let period: TimeInterval = 6
    /// Frames per second. Each frame makes the window server composite the menu bar again, which
    /// costs far more than drawing the mark.
    static let frameRate = 12.0

    /// Position in the cycle, from 0 up to 1.
    static func phase(at date: Date) -> Double {
        let cycles = date.timeIntervalSinceReferenceDate / period
        return cycles - cycles.rounded(.down)
    }
}

extension EnvironmentValues {
    /// False where views are rendered once, as in snapshots.
    var showsWorkingMotion: Bool {
        get { self[ShowsWorkingMotionKey.self] }
        set { self[ShowsWorkingMotionKey.self] = newValue }
    }
}

private struct ShowsWorkingMotionKey: EnvironmentKey {
    static let defaultValue = true
}
