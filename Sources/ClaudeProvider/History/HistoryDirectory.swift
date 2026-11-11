import Foundation

struct HistoryDirectory {
    let root: URL

    init?(home: URL, component: String) {
        let parent = home.deletingLastPathComponent().resolvingSymlinksInPath()
        let root = parent.appendingPathComponent(home.lastPathComponent).appendingPathComponent(component)
        // Resolving the parent allows system aliases such as /tmp, but not another home's history.
        guard root.resolvingSymlinksInPath().path == root.path else { return nil }
        self.root = root
    }

    func contains(_ resolved: URL) -> Bool {
        resolved.path == root.path || resolved.path.hasPrefix(root.path + "/")
    }

    func resolve(_ file: URL) -> URL? {
        let resolved = file.resolvingSymlinksInPath()
        return contains(resolved) && resolved.path != root.path ? resolved : nil
    }
}
