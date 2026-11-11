import CryptoKit
import Foundation

/// Stores regenerable Codable values as atomically replaced JSON files.
public struct DiskCache: Sendable {
    /// The directory containing the cache entries.
    public let directory: URL

    /// `~/Library/Caches/AgentBar`, or `AGENTBAR_CACHE_DIR` when set (diagnostics on a cold cache).
    public static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["AGENTBAR_CACHE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/AgentBar", isDirectory: true)
    }

    /// Uses the app cache directory unless a different directory is supplied.
    public init(directory: URL = DiskCache.defaultDirectory) {
        self.directory = directory
    }

    /// Returns nil for missing, unreadable, or corrupt entries.
    public func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = try? Data(contentsOf: location(for: key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Encodes a value and atomically replaces its cache entry.
    public func save<Value: Encodable>(_ value: Value, key: String) throws {
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: location(for: key), options: .atomic)
    }

    /// Removes an entry, treating an already missing entry as success.
    public func remove(key: String) throws {
        do {
            try FileManager.default.removeItem(at: location(for: key))
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    private func location(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined() + ".json"
        return directory.appendingPathComponent(filename)
    }
}
