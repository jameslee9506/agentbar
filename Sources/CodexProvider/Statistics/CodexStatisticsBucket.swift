import AgentBarCore

struct CodexStatisticsBucket: Hashable, Comparable, Sendable {
    let day: Int64
    let model: UInt32
    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.day, lhs.model) < (rhs.day, rhs.model) }
}

extension Dictionary where Key == CodexStatisticsBucket, Value == TokenCount {
    mutating func add(_ other: Self, sign: Int = 1) {
        for (bucket, tokens) in other {
            var value = self[bucket, default: .zero]
            value.input += sign * tokens.input
            value.output += sign * tokens.output
            value.cacheRead += sign * tokens.cacheRead
            value.cacheWrite += sign * tokens.cacheWrite
            if value == .zero { removeValue(forKey: bucket) }
            else { self[bucket] = value }
        }
    }
}
