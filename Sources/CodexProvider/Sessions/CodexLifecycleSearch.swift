import AgentBarCore
import Foundation

struct CodexLifecycleSearch {
    var boundary: UInt64
    private var summary = CodexLifecycleSummary()

    init(boundary: UInt64) { self.boundary = boundary }

    mutating func append(_ event: CodexLifecycleEvent) { summary.append(event) }

    /// One bounded step per poll; unchanged files continue searching on later polls.
    mutating func advance(file: URL, metadata: CodexThreadMetadata, home: URL, rollouts: CodexRolloutUsage) -> (CodexTurnState?, UInt64) {
        autoreleasepool {
            let end = boundary
            let start = end > 1024 * 1024 ? end - 1024 * 1024 : 0
            guard let handle = try? FileHandle(forReadingFrom: file) else { boundary = 0; return (nil, end) }
            defer { try? handle.close() }
            var aligned = start
            if start > 0 {
                guard (try? handle.seek(toOffset: start)) != nil,
                      let data = try? handle.read(upToCount: Int(end - start)) else { boundary = 0; return (nil, end) }
                aligned = data.firstIndex(of: 10).map { start + UInt64($0 + 1) } ?? end
            }
            var events: [CodexLifecycleEvent] = []
            var inherited = false
            let offset = (try? JSONLines.forEachLine(in: file, fromOffset: aligned, upTo: end, maximumLineBytes: 1024 * 1024) { bytes in
                guard let record = CodexRecord.decode(bytes) else { return }
                if let ordinal = record.ordinal, let first = metadata.historyStart, ordinal < first { inherited = true }
                guard metadata.owns(record) else { return }
                if let event = CodexLifecycleEvent(record) { events.append(event) }
                rollouts.observe(record, metadata: metadata, home: home)
            }) ?? aligned
            boundary = inherited ? 0 : aligned < end ? aligned : start
            for event in events.reversed() {
                if summary.prepend(event) { boundary = 0; break }
            }
            return (summary.turns, offset)
        }
    }
}
