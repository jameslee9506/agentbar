import AgentBarCore
import Foundation

struct StatisticsReport {
    struct Segment: Identifiable {
        let day: Date
        let series: String
        let tokens: Int
        var id: String { "\(day.timeIntervalSinceReferenceDate):\(series)" }
    }

    struct Row: Identifiable {
        let id: String
        let name: String
        let provider: ProviderKind?
        var tokens: TokenCount
    }

    let segments: [Segment]
    let rows: [Row]
    let start: Date
    let end: Date
    var total: TokenCount { rows.reduce(.zero) { $0 + $1.tokens } }

    init(accounts: [AccountState], selectedAccount: AccountID?, days: Int, now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        var rows: [String: Row] = [:]
        var daily: [Date: [String: Int]] = [:]
        for state in accounts where selectedAccount == nil || state.id == selectedAccount {
            if selectedAccount == nil {
                rows[state.id.description] = Row(
                    id: state.id.description, name: state.account.name,
                    provider: state.id.provider, tokens: .zero
                )
            }
            for day in state.statistics.days where day.day >= start && day.day < end {
                if selectedAccount == nil {
                    let key = state.id.description
                    rows[key]?.tokens += day.total
                    daily[day.day, default: [:]][key, default: 0] += day.total.total
                } else {
                    for (model, count) in day.byModel {
                        if rows[model] == nil { rows[model] = Row(id: model, name: model, provider: nil, tokens: .zero) }
                        rows[model]?.tokens += count
                        daily[day.day, default: [:]][model, default: 0] += count.total
                    }
                }
            }
        }
        self.rows = rows.values.sorted { $0.id < $1.id }
        segments = daily.keys.sorted().flatMap { day in
            daily[day, default: [:]].keys.sorted().compactMap { series in
                guard let tokens = daily[day]?[series], tokens > 0 else { return nil }
                return Segment(day: day, series: series, tokens: tokens)
            }
        }
    }
}
