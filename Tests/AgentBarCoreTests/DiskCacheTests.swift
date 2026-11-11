import AgentBarCore
import Foundation
import Testing

struct DiskCacheTests {
    private struct Entry: Codable, Equatable {
        let label: String
        let values: [Int]
    }

    @Test func roundTripsReplacesAndRemovesEntries() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let cache = DiskCache(directory: directory.url.appendingPathComponent("cache"))
        let first = Entry(label: "synthetic", values: [1, 2])
        let second = Entry(label: "updated", values: [3])
        let key = "../../synthetic/account"
        #expect(cache.load(Entry.self, key: key) == nil)
        try cache.save(first, key: key)
        #expect(cache.load(Entry.self, key: key) == first)
        try cache.save(second, key: key)
        #expect(cache.load(Entry.self, key: key) == second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.directory.path).count == 1)
        try cache.remove(key: key)
        try cache.remove(key: key)
        #expect(cache.load(Entry.self, key: key) == nil)
    }

    @Test func corruptAndMismatchedEntriesReadAsNil() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let cache = DiskCache(directory: directory.url)
        try cache.save(Entry(label: "synthetic", values: [1]), key: "entry")
        #expect(cache.load([Int].self, key: "entry") == nil)
        let files = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
        let entry = try #require(files.first)
        try Data("not JSON".utf8).write(to: entry)
        #expect(cache.load(Entry.self, key: "entry") == nil)
    }
}
