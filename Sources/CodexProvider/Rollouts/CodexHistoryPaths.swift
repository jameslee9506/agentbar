import Darwin
import Foundation

/// Parent resolutions are shared within a scan, never across filesystem changes.
struct CodexHistoryPaths {
    private let home: String
    private let resolvedHome: String
    private let roots: [String]
    private let resolvedRoots: [String]
    private var parents: [String: Bool] = [:]

    init(home: URL) {
        self.home = home.standardizedFileURL.path
        resolvedHome = home.resolvingSymlinksInPath().standardizedFileURL.path
        roots = Array(Set([home.path, self.home])).flatMap { [$0 + "/sessions/", $0 + "/archived_sessions/"] }
        resolvedRoots = [resolvedHome + "/sessions/", resolvedHome + "/archived_sessions/"]
    }

    mutating func stamp(_ file: URL) -> CodexFileStamp? {
        stamp(path: file.path)
    }

    mutating func stamp(path: String) -> CodexFileStamp? {
        guard !path.contains("/../") else { return nil }
        // File enumeration and callers can use different spellings of /var and /private/var.
        let path = roots.contains(where: path.hasPrefix) ? path : URL(fileURLWithPath: path).standardizedFileURL.path
        guard roots.contains(where: path.hasPrefix),
              let slash = path.lastIndex(of: "/") else { return nil }
        let parent = String(path[..<slash])
        let allowed: Bool
        if let cached = parents[parent] { allowed = cached }
        else {
            let resolved = URL(fileURLWithPath: parent).resolvingSymlinksInPath().standardizedFileURL.path + "/"
            allowed = resolvedRoots.contains(where: resolved.hasPrefix)
            parents[parent] = allowed
        }
        guard allowed else { return nil }
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        if info.st_mode & S_IFMT == S_IFLNK {
            let file = URL(fileURLWithPath: path)
            guard resolvedRoots.contains(where: file.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix) else { return nil }
            return CodexFileStamp(file)
        }
        return CodexFileStamp(info)
    }

    func containsDirectory(_ directory: URL) -> Bool {
        Self.contains(directory.standardizedFileURL.path, home: home)
            && Self.contains(directory.resolvingSymlinksInPath().standardizedFileURL.path, home: resolvedHome)
    }

    private static func contains(_ path: String, home: String) -> Bool {
        ["sessions", "archived_sessions"].contains { name in
            let root = home + "/" + name
            return path == root || path.hasPrefix(root + "/")
        }
    }
}
