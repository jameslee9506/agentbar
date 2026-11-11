import Foundation

struct CodexTurnState: Sendable {
    var running: [String: Date] = [:]
    var endedAt: Date?

    mutating func consume(_ record: CodexRecord) {
        if let event = CodexLifecycleEvent(record) { consume(event) }
    }

    mutating func consume(_ event: CodexLifecycleEvent) {
        if event.started {
            if let date = event.date { running[event.turn ?? "unidentified"] = date }
        } else {
            if let turn = event.turn { running.removeValue(forKey: turn) }
            else if running.count == 1 { running.removeAll() }
            if let date = event.date, endedAt.map({ date > $0 }) ?? true { endedAt = date }
        }
    }
}
