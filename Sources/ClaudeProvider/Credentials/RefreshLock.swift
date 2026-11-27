import Foundation

/// The lock the CLI holds while it renews a login: a directory in the home, and one beside the home
/// that older versions use. Holding both keeps a CLI of the same account from spending the refresh
/// token at the same moment.
struct RefreshLock {
    /// The age at which the CLI takes a lock for abandoned.
    static let staleAfter: TimeInterval = 60

    private let paths: [String]

    static func acquire(home: URL, now: Date = Date()) -> RefreshLock? {
        let current = home.appendingPathComponent(".oauth_refresh.lock").path
        let legacy = home.resolvingSymlinksInPath().path + ".lock"
        guard take(current, now: now) == .taken else { return nil }
        switch take(legacy, now: now) {
        case .taken: return RefreshLock(paths: [legacy, current])
        case .held:
            rmdir(current)
            return nil
        case .failed: return RefreshLock(paths: [current])
        }
    }

    func release() {
        for path in paths { rmdir(path) }
    }

    private enum Attempt { case taken, held, failed }

    private static func take(_ path: String, now: Date) -> Attempt {
        if mkdir(path, 0o755) == 0 { return .taken }
        guard errno == EEXIST else { return .failed }
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        guard let modified, now.timeIntervalSince(modified) > staleAfter, rmdir(path) == 0 else { return .held }
        return mkdir(path, 0o755) == 0 ? .taken : .held
    }
}
