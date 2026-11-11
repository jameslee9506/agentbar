import AgentBarCore
import Foundation

struct UsagePayload: Decodable, Sendable {
    let windows: [UsageWindow]

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }

    private struct Window: Decodable {
        let utilization: Double
        let resets_at: String?
    }

    private struct Limit: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable { let id: String?; let display_name: String? }
            let model: Model?
        }
        let kind: String?
        let group: String?
        let percent: Double?
        let resets_at: String?
        let scope: Scope?
    }

    private struct OptionalLimit: Decodable {
        let value: Limit?
        init(from decoder: any Decoder) throws { value = try? Limit(from: decoder) }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var mapped: [String: UsageWindow] = [:]
        func legacy(_ key: String, id: String, title: String) {
            guard let value = try? container.decode(Window.self, forKey: Key(key)), value.utilization.isFinite else { return }
            mapped[id] = UsageWindow(id: id, title: title, usedPercent: value.utilization,
                                     resetsAt: value.resets_at.flatMap(Timestamps.parse))
        }
        legacy("five_hour", id: "session", title: "5h")
        legacy("seven_day", id: "weekly", title: "Week")
        legacy("seven_day_opus", id: "weekly.opus", title: "Opus")
        legacy("seven_day_sonnet", id: "weekly.sonnet", title: "Sonnet")
        let limits = (try? container.decode([OptionalLimit].self, forKey: Key("limits"))) ?? []
        for entry in limits {
            guard let limit = entry.value, let percent = limit.percent, percent.isFinite else { continue }
            if limit.kind == "weekly_all" {
                mapped["weekly"] = UsageWindow(id: "weekly", title: "Week", usedPercent: percent,
                                                resetsAt: limit.resets_at.flatMap(Timestamps.parse))
            } else if limit.kind == "weekly_scoped", limit.group == "weekly",
                      let name = limit.scope?.model?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty {
                let titleSlug = Self.slug(name)
                let modelSlug = Self.slug(limit.scope?.model?.id ?? name)
                guard !modelSlug.isEmpty, titleSlug != "all-models", modelSlug != "all-models",
                      !modelSlug.hasSuffix("-all-models") else { continue }
                // A legacy model window and its newer limits entry represent the same quota.
                let family = ["opus", "sonnet"].first { model in
                    [titleSlug, modelSlug].contains { value in
                        value == model || value.hasPrefix(model + "-")
                            || value == "claude-" + model || value.hasPrefix("claude-" + model + "-")
                    }
                }
                let id = "weekly." + (family ?? modelSlug)
                mapped[id] = UsageWindow(id: id, title: name, usedPercent: percent,
                                         resetsAt: limit.resets_at.flatMap(Timestamps.parse))
            }
        }
        windows = mapped.values.sorted { left, right in
            func order(_ window: UsageWindow) -> Int {
                window.id == "session" ? 0 : (window.id == "weekly" ? 1 : 2)
            }
            return (order(left), left.id) < (order(right), right.id)
        }
    }

    private static func slug(_ value: String) -> String {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
    }
}
