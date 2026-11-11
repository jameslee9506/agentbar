import AgentBarCore
import Foundation

struct CodexOwnedThread {
    let metadata: CodexThreadMetadata
    var turns: CodexTurnState
    var stamp: CodexFileStamp
    var offset: UInt64
    var anchor: String?
    private var search: CodexLifecycleSearch

    var isSearching: Bool { search.boundary > 0 }

    init?(file: URL, home: URL, rollouts: CodexRolloutUsage) {
        guard let metadata = CodexRolloutFile.metadata(file), let stamp = CodexFileStamp(file) else { return nil }
        self.metadata = metadata
        self.stamp = stamp
        turns = CodexTurnState()
        search = CodexLifecycleSearch(boundary: stamp.size)
        let (seed, end) = search.advance(file: file, metadata: metadata, home: home, rollouts: rollouts)
        if let seed { turns = seed }
        offset = end
        anchor = CodexRolloutFile.anchor(file, endingAt: offset)
        if !isSearching { search = CodexLifecycleSearch(boundary: 0) }
    }

    func canAppend(file: URL, stamp: CodexFileStamp) -> Bool {
        guard self.stamp.inode == stamp.inode, self.stamp.device == stamp.device, stamp.size >= offset else { return false }
        if self.stamp == stamp { return true }
        guard stamp.size > self.stamp.size else { return false }
        return anchor == CodexRolloutFile.anchor(file, endingAt: offset)
    }

    mutating func update(file: URL, stamp: CodexFileStamp, home: URL, rollouts: CodexRolloutUsage) {
        if self.stamp != stamp { read(file: file, through: stamp.size, home: home, rollouts: rollouts) }
        self.stamp = stamp
        if isSearching {
            let (seed, _) = search.advance(file: file, metadata: metadata, home: home, rollouts: rollouts)
            if let seed { turns = seed }
            if !isSearching { search = CodexLifecycleSearch(boundary: 0) }
        }
    }

    private mutating func read(file: URL, through end: UInt64, home: URL, rollouts: CodexRolloutUsage) {
        if let end = try? JSONLines.forEachLine(in: file, fromOffset: offset, upTo: end, maximumLineBytes: 1024 * 1024, { bytes in
            guard let record = CodexRecord.decode(bytes), metadata.owns(record) else { return }
            if let event = CodexLifecycleEvent(record) {
                if isSearching { search.append(event) }
                turns.consume(event)
            }
            rollouts.observe(record, metadata: metadata, home: home)
        }) { offset = end }
        anchor = CodexRolloutFile.anchor(file, endingAt: offset)
    }
}
