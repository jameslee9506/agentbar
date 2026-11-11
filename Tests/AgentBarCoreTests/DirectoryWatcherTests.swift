import AgentBarCore
import Foundation
import Testing

struct DirectoryWatcherTests {
    @Test(arguments: [false, true])
    func receivesRecursiveFileEvents(rootInitiallyMissing: Bool) async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let first = directory.url.appendingPathComponent("first", isDirectory: true)
        let second = directory.url.appendingPathComponent("second", isDirectory: true)
        if !rootInitiallyMissing {
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        }
        let watcher = try DirectoryWatcher(directories: [first, second], latency: 0.02)
        defer { watcher.stop() }
        let nested = first.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let firstFile = nested.appendingPathComponent("first.jsonl")
        let secondFile = second.appendingPathComponent("second.jsonl")
        try Data("first\n".utf8).write(to: firstFile)
        try Data("second\n".utf8).write(to: secondFile)
        let expected = Set([firstFile, secondFile].map { $0.resolvingSymlinksInPath().path })

        let received = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var seen = Set<String>()
                for await batch in watcher.events {
                    seen.formUnion(batch)
                    if expected.isSubset(of: seen) { return true }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        #expect(received)
    }

    @Test func cancellationFinishesStream() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let watcher = try DirectoryWatcher(directories: [directory.url])
        let consumer = Task {
            for await _ in watcher.events {}
        }
        consumer.cancel()
        await consumer.value
        var iterator = watcher.events.makeAsyncIterator()
        #expect(await iterator.next() == nil)
        watcher.stop()
    }

    @Test func deallocationFinishesStream() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        var watcher: DirectoryWatcher? = try DirectoryWatcher(directories: [directory.url])
        weak let reference = watcher
        let events = try #require(watcher?.events)
        watcher = nil
        #expect(reference == nil)
        var iterator = events.makeAsyncIterator()
        while await iterator.next() != nil {}
    }
}
