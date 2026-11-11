import AgentBarCore
@testable import CodexProvider
import Foundation
import Testing

struct CodexStatisticsReaderTests {
    @Test func oversizedPartialLinesAreSkippedAndSnapshotLimitsAreRespected() throws {
        let fixture = try CodexFixture()
        let home = try fixture.home()
        let first = fixture.metadata() + fixture.context()
        let file = try fixture.rollout(home, lines: [first])
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        let block = Data(repeating: 120, count: 64 * 1024)
        for _ in 0..<128 { try handle.write(contentsOf: block) }
        try handle.close()
        var visits = 0
        let stamp = try #require(CodexFileStamp(file))
        let initial = try JSONLines.forEachLine(in: file, maximumLineBytes: 2 * 1024 * 1024) { _ in visits += 1 }
        #expect(visits == 2)
        #expect(initial == UInt64(first.utf8.count))
        #expect(stamp.size == initial + 8 * 1024 * 1024)
        try fixture.append(["\n", fixture.ledger("new")], to: file)
        visits = 0
        let appended = try JSONLines.forEachLine(in: file, fromOffset: initial, maximumLineBytes: 2 * 1024 * 1024) { _ in visits += 1 }
        #expect(visits == 1)
        #expect(appended == CodexFileStamp(file)?.size)
        visits = 0
        let bounded = try JSONLines.forEachLine(in: file, upTo: stamp.size, maximumLineBytes: 2 * 1024 * 1024) { _ in visits += 1 }
        #expect(visits == 2)
        #expect(bounded == initial)
    }
}
