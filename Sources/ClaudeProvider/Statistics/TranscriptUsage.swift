import AgentBarCore
import Foundation

struct TranscriptUsage: Equatable, Sendable {
    let timestamp: Date
    let tokens: TokenCount
    let offset: UInt64
    let file: UInt32
    var model: UInt32
    let flags: UInt8

    var complete: Bool { flags & 1 != 0 }
    var sidechain: Bool { flags & 2 != 0 }

    func isPreferred(to other: Self) -> Bool {
        if complete != other.complete { return complete }
        if sidechain != other.sidechain { return !sidechain }
        if timestamp != other.timestamp { return timestamp > other.timestamp }
        if offset != other.offset { return offset > other.offset }
        return file < other.file
    }
}
