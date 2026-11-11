import AgentBarCore
@testable import CodexProvider
import Foundation

final class CodexFixture: Sendable {
    static let date = Date(timeIntervalSince1970: 1_794_312_000)
    let root: URL
    let cache: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("AgentBarCodexTests-" + UUID().uuidString, isDirectory: true)
        cache = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func home(_ name: String = ".codex") throws -> URL {
        let home = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    func auth(
        _ home: URL, mode: String? = "chatgpt", accountID: String? = "account-example",
        expiry: Date = date.addingTimeInterval(86400), email: String = "person@example.test",
        accessAccount: String = "account-example", idExpiry: Date = date.addingTimeInterval(-3600)
    ) throws {
        var tokens: [String: Any] = [
            "access_token": Self.jwt([
                "exp": expiry.timeIntervalSince1970,
                "https://api.openai.com/auth": ["chatgpt_account_id": accessAccount, "chatgpt_plan_type": "pro", "chatgpt_user_id": "user-example"],
                "https://api.openai.com/profile": ["email": "access@example.test"],
            ]),
            "id_token": Self.jwt([
                "exp": idExpiry.timeIntervalSince1970, "email": email,
                "https://api.openai.com/auth": ["chatgpt_account_id": "id-account-example", "chatgpt_plan_type": "plus"],
            ]),
            "refresh_token": "unused-synthetic-value",
        ]
        tokens["account_id"] = accountID
        var object: [String: Any] = ["tokens": tokens]
        object["auth_mode"] = mode
        try json(object).write(to: home.appendingPathComponent("auth.json"))
        try FileManager.default.setAttributes([.modificationDate: Self.date.addingTimeInterval(-1000)], ofItemAtPath: home.appendingPathComponent("auth.json").path)
    }

    func account(_ home: URL) -> Account {
        Account(id: AccountID(provider: .codex, home: home.lastPathComponent), name: "example", home: home)
    }

    func provider(processes: FakeCodexProcesses = FakeCodexProcesses(), transport: FakeCodexTransport = FakeCodexTransport(), calendar: Calendar = .current) -> CodexProvider {
        CodexProvider(homeRoot: root, processes: processes, transport: transport, clock: { Self.date }, cacheDirectory: cache, calendar: calendar, pollInterval: .milliseconds(20))
    }

    func rollout(_ home: URL, name: String = "thread", lines: [String]) throws -> URL {
        let directory = home.appendingPathComponent("sessions/2026/11/10")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name + ".jsonl")
        try Data(lines.joined().utf8).write(to: file)
        return file
    }

    func append(_ lines: [String], to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines.joined().utf8))
    }

    func metadata(_ id: String = "thread", parent: String? = nil, boundary: Int? = nil, creator: String? = "account-example", session: String? = "shared-session") -> String {
        var payload: [String: Any] = ["id": id, "cwd": "/projects/example"]
        payload["session_id"] = session
        payload["parent_thread_id"] = parent
        payload["forked_from_id"] = parent
        payload["subagent_history_start_ordinal"] = boundary
        payload["creator_account_id"] = creator
        return row("session_meta", payload, ordinal: 0)
    }

    func context(_ turn: String? = "turn", model: String = "model-example", ordinal: Int = 1) -> String {
        var payload: [String: Any] = ["model": model]
        payload["turn_id"] = turn
        return row("turn_context", payload, ordinal: ordinal)
    }

    func event(_ type: String, turn: String? = "turn", at: Date = date, ordinal: Int = 2, root: String? = nil) -> String {
        var payload: [String: Any] = ["type": type]
        payload["turn_id"] = turn
        payload["root_turn_id"] = root
        payload[type == "task_started" ? "started_at" : "completed_at"] = at.timeIntervalSince1970
        return row("event_msg", payload, at: at, ordinal: ordinal)
    }

    func ledger(
        _ response: String, thread: String = "thread", turn: String = "turn", input: Int = 100,
        cached: Int = 40, output: Int = 20, written: Int = 0, at: Date = date, ordinal: Int = 3,
        cumulative: [String: Any]? = nil, session: String = "shared-session"
    ) -> String {
        var payload: [String: Any] = [
            "thread_id": thread, "turn_id": turn, "session_id": session, "response_id": response,
            "usage": usage(input: input, cached: cached, output: output, written: written),
        ]
        payload["thread_token_usage"] = cumulative
        return row("token_usage_record", payload, at: at, ordinal: ordinal)
    }

    func counter(input: Int, cached: Int = 0, output: Int = 0, last: [String: Any]? = nil, at: Date = date, ordinal: Int = 4) -> String {
        var info: [String: Any] = ["total_token_usage": usage(input: input, cached: cached, output: output)]
        info["last_token_usage"] = last
        return row("event_msg", ["type": "token_count", "info": info], at: at, ordinal: ordinal)
    }

    func quota(_ percent: Int, at: Date = date) -> String {
        row("event_msg", ["type": "token_count", "info": NSNull(), "rate_limits": [
            "limit_id": "codex", "primary": ["used_percent": percent, "window_minutes": 10080, "resets_at": at.addingTimeInterval(86400).timeIntervalSince1970], "secondary": NSNull(),
        ]], at: at)
    }

    func usage(input: Int, cached: Int = 0, output: Int = 0, written: Int = 0) -> [String: Any] {
        ["input_tokens": input, "cached_input_tokens": cached, "cache_write_input_tokens": written, "output_tokens": output, "reasoning_output_tokens": output / 2, "total_tokens": input + output]
    }

    func row(_ type: String, _ payload: [String: Any], at: Date = date, ordinal: Int = 2) -> String {
        let encoded = String(decoding: try! json(payload), as: UTF8.self)
        return "{\"timestamp\":\"\(at.ISO8601Format())\",\"ordinal\":\(ordinal),\"type\":\"\(type)\",\"payload\":\(encoded)}\n"
    }

    func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }

    static func jwt(_ claims: [String: Any]) -> String {
        let encoded = try! JSONSerialization.data(withJSONObject: claims).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "synthetic.\(encoded).signature"
    }
}
