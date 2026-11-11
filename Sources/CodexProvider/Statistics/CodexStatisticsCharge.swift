import AgentBarCore
import Foundation

/// A transient accounting decision, consumed immediately and never cached.
struct CodexStatisticsCharge {
    let key: CodexStatisticsID
    let turn: CodexStatisticsID
    let ledger: Bool
    let bucket: CodexStatisticsBucket
    let tokens: TokenCount
    var cumulative: CodexTokenUsage? = nil
    var baseline: CodexTokenUsage? = nil
    var timestamp: Date? = nil
}
