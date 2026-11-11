import AgentBarCore
import CryptoKit
import Foundation

enum CodexRolloutFile {
    static func metadata(_ file: URL) -> CodexThreadMetadata? {
        var metadata: CodexThreadMetadata?
        _ = try? JSONLines.forEachLine(in: file, upTo: 1024 * 1024, maximumLineBytes: 1024 * 1024) { bytes in
            metadata = CodexRecord.decode(bytes).flatMap(CodexThreadMetadata.init)
            throw FirstLine.read
        }
        return metadata
    }

    static func anchor(_ file: URL, endingAt offset: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let count = min(offset, 256)
        guard (try? handle.seek(toOffset: offset - count)) != nil,
              let data = try? handle.read(upToCount: Int(count)), data.count == Int(count)
        else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func inventory(home: URL, since: Date) -> [String: CodexFileStamp] {
        var files: [String: CodexFileStamp] = [:]
        var paths = CodexHistoryPaths(home: home)
        let prefix = home.standardizedFileURL.path + "/"
        for name in ["sessions", "archived_sessions"] {
            let root = home.appendingPathComponent(name)
            guard paths.containsDirectory(root) else { continue }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                let file = file.standardizedFileURL
                if let stamp = paths.stamp(file), stamp.modifiedAt >= since { files[String(file.path.dropFirst(prefix.count))] = stamp }
            }
        }
        return files
    }

    static func recentFiles(home: URL, limit: Int = 12) -> [URL] {
        var paths = CodexHistoryPaths(home: home)
        var directories = [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")]
        var candidates: [(URL, Date)] = []
        var inspected = 0
        while !directories.isEmpty, inspected < 24 {
            let directory = directories.removeFirst()
            inspected += 1
            guard paths.containsDirectory(directory),
                  let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            var nested: [URL] = []
            for child in children {
                if child.pathExtension == "jsonl", let stamp = paths.stamp(child) { candidates.append((child, stamp.modifiedAt)) }
                else if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { nested.append(child) }
            }
            directories.insert(contentsOf: nested.sorted { $0.lastPathComponent > $1.lastPathComponent }, at: 0)
            if candidates.count >= limit { break }
        }
        return candidates.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private enum FirstLine: Error { case read }
}
