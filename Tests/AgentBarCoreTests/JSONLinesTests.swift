import AgentBarCore
import Foundation
import Testing

struct JSONLinesTests {
    @Test func resumesAfterAnAppendedPartialLine() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("events.jsonl")
        try Data("{\"n\":1}\n{\"n\":".utf8).write(to: file)
        var lines: [Data] = []
        var offset = try JSONLines.forEachLine(in: file) { lines.append(Data($0)) }
        #expect(lines == [Data("{\"n\":1}".utf8)])
        #expect(offset == UInt64(Data("{\"n\":1}\n".utf8).count))
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("2}\n{\"n\":3}".utf8))
        lines.removeAll()
        offset = try JSONLines.forEachLine(in: file, fromOffset: offset) { lines.append(Data($0)) }
        #expect(lines == [Data("{\"n\":2}".utf8)])
        try handle.write(contentsOf: Data("\n".utf8))
        lines.removeAll()
        offset = try JSONLines.forEachLine(in: file, fromOffset: offset) { lines.append(Data($0)) }
        #expect(lines == [Data("{\"n\":3}".utf8)])
        #expect(offset == (try handle.offset()))
    }

    @Test func preservesRawBytesAndLinesAcrossReadBoundaries() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("large-line.jsonl")
        let longLine = Data(repeating: 0x61, count: 256 * 1024 + 7)
        var contents = longLine
        contents.append(contentsOf: [0x0A, 0x0A, 0xFF, 0x00, 0x0D, 0x0A, 0x78])
        try contents.write(to: file)
        var lines: [Data] = []
        let offset = try JSONLines.forEachLine(in: file) { lines.append(Data($0)) }
        #expect(lines == [longLine, Data(), Data([0xFF, 0x00, 0x0D])])
        #expect(offset == UInt64(contents.count - 1))
        var bounded: [Data] = []
        let boundedOffset = try JSONLines.forEachLine(in: file, maximumLineBytes: 16) { bounded.append(Data($0)) }
        #expect(bounded == [Data(), Data([0xFF, 0x00, 0x0D])])
        #expect(boundedOffset == offset)
    }

    @Test func readsBoundedTailsAndIgnoresIncompleteLines() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("tail.jsonl")
        try Data("first\nsecond\nthird\npartial".utf8).write(to: file)
        #expect(try JSONLines.tailLines(in: file, count: 2) == [Data("second".utf8), Data("third".utf8)])
        #expect(try JSONLines.tailLines(in: file, count: 1) == [Data("third".utf8)])
        #expect(try JSONLines.tailLines(in: file, count: 0).isEmpty)
        #expect(try JSONLines.tailBytes(in: file, maximumCount: 7) == Data("partial".utf8))
        #expect(try JSONLines.tailBytes(in: file, maximumCount: 0).isEmpty)
        #expect(try JSONLines.tailLines(in: file, count: 10, maximumBytes: 16) == [Data("third".utf8)])
        #expect(try JSONLines.tailLines(in: file, count: 10, maximumBytes: 13) == [Data("third".utf8)])
        #expect(try JSONLines.tailLines(in: file, count: 10, maximumBytes: 8).isEmpty)
        try Data("one\n\n".utf8).write(to: file)
        #expect(try JSONLines.tailLines(in: file, count: 1) == [Data()])
        #expect(try JSONLines.tailLines(in: file, count: 10) == [Data("one".utf8), Data()])
        try Data("unfinished".utf8).write(to: file)
        #expect(try JSONLines.tailLines(in: file, count: 10).isEmpty)
        try Data().write(to: file)
        #expect(try JSONLines.forEachLine(in: file) { _ in Issue.record("Unexpected empty-file line") } == 0)
        #expect(try JSONLines.tailLines(in: file, count: 10).isEmpty)
    }

    @Test func streamsLargeFileWithoutAccumulatingLines() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("throughput.jsonl")
        let lineLength = 1024
        let lineCount = 16_384
        var contents = Data(repeating: 0x61, count: lineLength * lineCount)
        for index in stride(from: lineLength - 1, to: contents.count, by: lineLength) {
            contents[index] = 0x0A
        }
        try contents.write(to: file)
        var received = 0
        var byteCount = 0
        let start = ContinuousClock.now
        let offset = try JSONLines.forEachLine(in: file) {
            received += 1
            byteCount += $0.count
        }
        let elapsed = start.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        print(String(format: "JSONLines read/split throughput: %.0f MB/s", Double(contents.count) / seconds / 1_000_000))
        #expect(received == lineCount)
        #expect(byteCount == lineCount * (lineLength - 1))
        #expect(offset == UInt64(contents.count))
    }
}
