import Foundation

struct CodexRecord {
    let type: String
    let payload: [String: Any]
    let timestamp: Date?
    let ordinal: Int64?

    var event: String? { payload["type"] as? String }

    static func decode(_ bytes: UnsafeRawBufferPointer) -> Self? {
        guard relevant(bytes),
              let object = (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any]
        else { return nil }
        return Self(type: type, payload: payload, timestamp: date(object["timestamp"]), ordinal: (object["ordinal"] as? NSNumber)?.int64Value)
    }

    static func date(_ value: Any?) -> Date? {
        if let value = value as? NSNumber, value.doubleValue.isFinite { return Date(timeIntervalSince1970: value.doubleValue) }
        guard let value = value as? String else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle().parse(value))
    }

    private static func relevant(_ bytes: UnsafeRawBufferPointer) -> Bool {
        // Inspect only structural keys at the front of the envelope, never matching message text.
        var depth = 0
        var index = 0
        var types: [Int: String] = [:]
        let limit = min(bytes.count, 2048)
        while index < limit {
            let byte = bytes[index]
            if byte == 123 { depth += 1 }
            else if byte == 125 { depth -= 1 }
            else if byte == 34 {
                let start = index + 1
                index += 1
                while index < limit {
                    if bytes[index] == 92 { index += 2; continue }
                    if bytes[index] == 34 { break }
                    index += 1
                }
                guard index < limit else { break }
                if depth <= 2, index - start == 4,
                   bytes[start] == 116, bytes[start + 1] == 121, bytes[start + 2] == 112, bytes[start + 3] == 101 {
                    var cursor = index + 1
                    while cursor < limit, bytes[cursor] == 32 || bytes[cursor] == 9 { cursor += 1 }
                    if cursor < limit, bytes[cursor] == 58 {
                        cursor += 1
                        while cursor < limit, bytes[cursor] == 32 || bytes[cursor] == 9 { cursor += 1 }
                        if cursor < limit, bytes[cursor] == 34 {
                            let valueStart = cursor + 1
                            cursor += 1
                            while cursor < limit, bytes[cursor] != 34 { cursor += 1 }
                            if cursor < limit { types[depth] = String(decoding: bytes[valueStart..<cursor], as: UTF8.self) }
                        }
                    }
                }
            }
            index += 1
            if let type = types[1] {
                if type == "session_meta" || type == "turn_context" || type == "token_usage_record" { return true }
                if type != "event_msg" { return false }
                if let event = types[2] { return ["token_count", "task_started", "task_complete", "turn_aborted"].contains(event) }
            }
        }
        // Small reordered envelopes remain readable; large content rows stay bounded.
        return bytes.count <= 4096
    }
}
