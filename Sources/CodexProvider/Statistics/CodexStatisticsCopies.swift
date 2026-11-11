import AgentBarCore
import Foundation

/// Copied histories need two passes. Ledger entries retain only fixed-width selectors;
/// legacy copies reconcile cumulative observations before assigning daily deltas.
enum CodexStatisticsCopies {
    static func rebuild(
        files: [(String, CodexFileStamp)], home: URL, since: Date, calendar: Calendar,
        names: inout CodexStatisticsModels, rollouts: CodexRolloutUsage
    ) -> [String: CodexStatisticsCheckpoint] {
        var responses: [CodexStatisticsID: Choice] = [:]
        var counters: [CodexStatisticsID: Counter] = [:]
        var ledgerTurns: Set<CodexStatisticsID> = []
        var snapshots: [CodexFileStamp] = []
        for (index, source) in files.enumerated() {
            autoreleasepool {
                var checkpoint = CodexStatisticsCheckpoint(stamp: source.1)
                var event = 0
                checkpoint.read(file: home.appendingPathComponent(source.0), home: home, since: since, calendar: calendar, names: &names, rollouts: rollouts) { charge in
                    defer { event += 1 }
                    let choice = Choice(file: index, event: event, knownModel: charge.bucket.model != 0)
                    if charge.ledger {
                        if responses[charge.key].map({ !$0.knownModel && choice.knownModel }) ?? true { responses[charge.key] = choice }
                    } else if let cumulative = charge.cumulative, let baseline = charge.baseline, let timestamp = charge.timestamp {
                        let candidate = Counter(choice: choice, turn: charge.turn, cumulative: cumulative, baseline: baseline, timestamp: timestamp)
                        if let previous = counters[charge.key] {
                            if (!previous.choice.knownModel && choice.knownModel) || candidate.deltaTotal < previous.deltaTotal { counters[charge.key] = candidate }
                        } else { counters[charge.key] = candidate }
                    }
                    return nil
                }
                ledgerTurns.formUnion(checkpoint.ledgerTurns)
                snapshots.append(checkpoint.stamp)
            }
        }
        var highWater = CodexTokenUsage.zero
        let ordered = counters.keys.sorted {
            let left = counters[$0]!, right = counters[$1]!
            if left.timestamp != right.timestamp { return left.timestamp < right.timestamp }
            if left.cumulative.tokens.total != right.cumulative.tokens.total { return left.cumulative.tokens.total < right.cumulative.tokens.total }
            if left.cumulative.cached != right.cumulative.cached { return left.cumulative.cached < right.cumulative.cached }
            if left.choice.file != right.choice.file { return left.choice.file < right.choice.file }
            return left.choice.event < right.choice.event
        }
        for key in ordered {
            guard let counter = counters[key] else { continue }
            highWater.retainHighWater(counter.baseline)
            let tokens = counter.cumulative.delta(from: highWater)?.tokens ?? .zero
            highWater.retainHighWater(counter.cumulative)
            counters[key]?.tokens = ledgerTurns.contains(counter.turn) ? .zero : tokens
        }
        var result: [String: CodexStatisticsCheckpoint] = [:]
        for (index, source) in files.enumerated() {
            autoreleasepool {
                var checkpoint = CodexStatisticsCheckpoint(stamp: snapshots[index])
                var event = 0
                checkpoint.read(file: home.appendingPathComponent(source.0), home: home, since: since, calendar: calendar, through: snapshots[index].size, names: &names, rollouts: rollouts) { charge in
                    defer { event += 1 }
                    if charge.ledger {
                        guard let choice = responses[charge.key], choice.file == index && choice.event == event else { return nil }
                        return charge.tokens
                    }
                    guard !ledgerTurns.contains(charge.turn), let counter = counters[charge.key],
                          counter.choice.file == index && counter.choice.event == event else { return nil }
                    return counter.tokens
                }
                result[source.0] = checkpoint
            }
        }
        return result
    }

    private struct Choice {
        let file: Int
        let event: Int
        let knownModel: Bool
    }

    private struct Counter {
        let choice: Choice
        let turn: CodexStatisticsID
        let cumulative: CodexTokenUsage
        let baseline: CodexTokenUsage
        let timestamp: Date
        var tokens = TokenCount.zero
        var deltaTotal: Int { cumulative.delta(from: baseline)?.tokens.total ?? 0 }
    }
}
