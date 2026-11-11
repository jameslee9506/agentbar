import Foundation

struct CodexThreadMetadata: Codable, Sendable {
    let id: String
    let sessionID: String?
    let parentID: String?
    let forked: Bool
    let historyStart: Int64?
    let directory: String?
    let creatorAccountDigest: String?
    let creatorUserDigest: String?

    init?(record: CodexRecord) {
        guard record.type == "session_meta", let id = record.payload["id"] as? String, !id.isEmpty else { return nil }
        let payload = record.payload
        let source = payload["source"] as? [String: Any]
        let subagent = source?["subagent"] as? [String: Any]
        let spawn = subagent?["thread_spawn"] as? [String: Any]
        self.id = id
        sessionID = payload["session_id"] as? String
        parentID = payload["parent_thread_id"] as? String ?? spawn?["parent_thread_id"] as? String
        forked = payload["forked_from_id"] is String || parentID != nil
        historyStart = (payload["subagent_history_start_ordinal"] as? NSNumber)?.int64Value
        directory = payload["cwd"] as? String
        creatorAccountDigest = (payload["creator_account_id"] as? String).map(CodexCredential.digest)
        creatorUserDigest = (payload["creator_user_id"] as? String).map(CodexCredential.digest)
    }

    func owns(_ record: CodexRecord) -> Bool {
        guard let historyStart else { return true }
        guard let ordinal = record.ordinal else { return false }
        return ordinal >= historyStart
    }
}
