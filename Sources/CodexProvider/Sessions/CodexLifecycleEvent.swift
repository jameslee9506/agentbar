import Foundation

struct CodexLifecycleEvent {
    let started: Bool
    let turn: String?
    let root: String?
    let date: Date?

    init?(_ record: CodexRecord) {
        guard record.type == "event_msg" else { return nil }
        switch record.event {
        case "task_started": started = true
        case "task_complete", "turn_aborted": started = false
        default: return nil
        }
        turn = record.payload["turn_id"] as? String
        root = record.payload["root_turn_id"] as? String
        date = CodexRecord.date(record.payload[started ? "started_at" : "completed_at"]) ?? record.timestamp
        if started && date == nil { return nil }
    }
}
