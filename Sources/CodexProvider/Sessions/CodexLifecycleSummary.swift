import Foundation

/// Named events commute across different turn IDs. Only ID-less terminals need
/// separate segments, because they close a turn only when exactly one is running.
struct CodexLifecycleSummary {
    private var segments = [Segment()]
    private var completed: Set<String> = []
    private var endedAt: Date?

    var turns: CodexTurnState {
        var turns = CodexTurnState()
        for segment in segments.reversed() {
            for event in segment.latest.values { turns.consume(event) }
            if let terminal = segment.terminal { turns.consume(terminal) }
        }
        turns.endedAt = endedAt
        return turns
    }

    /// Returns true at the start of a completed root turn. Root turns in a thread
    /// are serial; nested turns share its root ID and cannot supply this boundary.
    mutating func prepend(_ event: CodexLifecycleEvent) -> Bool {
        observeEnd(event)
        let last = segments.count - 1
        if !event.started, event.turn == nil {
            segments.append(Segment(terminal: event))
        } else {
            let key = event.turn ?? "unidentified"
            if segments[last].latest[key] == nil { segments[last].latest[key] = event }
        }
        if !event.started, let turn = event.turn { completed.insert(turn) }
        guard event.started, let turn = event.turn, event.root == turn else { return false }
        return completed.contains(turn)
    }

    mutating func append(_ event: CodexLifecycleEvent) {
        observeEnd(event)
        if !event.started, event.turn == nil {
            segments[0].terminal = event
            segments.insert(Segment(), at: 0)
        } else { segments[0].latest[event.turn ?? "unidentified"] = event }
        if !event.started, let turn = event.turn { completed.insert(turn) }
    }

    private mutating func observeEnd(_ event: CodexLifecycleEvent) {
        if !event.started, let date = event.date, endedAt.map({ date > $0 }) ?? true { endedAt = date }
    }

    private struct Segment {
        var latest: [String: CodexLifecycleEvent] = [:]
        var terminal: CodexLifecycleEvent?
    }
}
