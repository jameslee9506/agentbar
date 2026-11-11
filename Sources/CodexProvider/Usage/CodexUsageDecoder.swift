import AgentBarCore
import Foundation

enum CodexUsageDecoder {
    static func response(_ data: Data, at date: Date) -> UsageSnapshot? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["rate_limit"] is [String: Any] || object["additional_rate_limits"] is [[String: Any]]
        else { return nil }
        var windows = mainWindows(object["rate_limit"] as? [String: Any], at: date, rollout: false)
        for (index, additional) in ((object["additional_rate_limits"] as? [[String: Any]]) ?? []).enumerated() {
            let name = additional["limit_name"] as? String ?? additional["metered_feature"] as? String ?? "Limit \(index + 1)"
            let key = additional["metered_feature"] as? String ?? name
            let limits = mainWindows(additional["rate_limit"] as? [String: Any], at: date, rollout: false)
            windows += limits.map {
                UsageWindow(id: "additional.\(key).\($0.id)", title: name, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt)
            }
        }
        return UsageSnapshot(windows: windows, capturedAt: date)
    }

    static func rollout(_ object: [String: Any], at date: Date) -> UsageSnapshot {
        var windows = mainWindows(object, at: date, rollout: true)
        if let id = object["limit_id"] as? String, id != "codex" {
            let name = object["limit_name"] as? String ?? id
            windows = windows.map {
                UsageWindow(id: "additional.\(id).\($0.id)", title: name, usedPercent: $0.usedPercent, resetsAt: $0.resetsAt)
            }
        }
        return UsageSnapshot(windows: windows, capturedAt: date)
    }

    private static func mainWindows(_ object: [String: Any]?, at date: Date, rollout: Bool) -> [UsageWindow] {
        guard let object else { return [] }
        let keys = rollout ? ["primary", "secondary"] : ["primary_window", "secondary_window"]
        return keys.enumerated().compactMap { index, key -> (Double, UsageWindow)? in
            guard let window = object[key] as? [String: Any], let used = number(window["used_percent"]) else { return nil }
            let seconds = number(window[rollout ? "window_minutes" : "limit_window_seconds"]).flatMap { value -> Double? in
                let seconds = value * (rollout ? 60 : 1)
                return seconds > 0 && seconds.isFinite && seconds < Double(Int.max / 2) ? seconds : nil
            }
            let reset = number(window[rollout ? "resets_at" : "reset_at"]).flatMap(resetDate)
                ?? number(window["reset_after_seconds"]).flatMap { resetDate(date.timeIntervalSince1970 + $0) }
            let id: String
            let title: String
            switch seconds {
            case 18000: id = "session"; title = "5h"
            case 604800: id = "weekly"; title = "Week"
            case let seconds? where seconds > 0:
                id = "window.\(Int(seconds))"
                title = duration(seconds)
            default: id = index == 0 ? "session" : "weekly"; title = index == 0 ? "Session" : "Week"
            }
            return (seconds ?? .greatestFiniteMagnitude, UsageWindow(id: id, title: title, usedPercent: used, resetsAt: reset))
        }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    private static func resetDate(_ seconds: Double) -> Date? {
        guard seconds >= 0, seconds < 253_402_300_800 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func duration(_ seconds: Double) -> String {
        let value = min(seconds, Double(Int.max / 2))
        if value >= 86400 { return "\(Int(value / 86400))d" }
        if value >= 3600 { return "\(Int(value / 3600))h" }
        if value >= 60 { return "\(Int(value / 60))m" }
        return "\(Int(value))s"
    }
}
