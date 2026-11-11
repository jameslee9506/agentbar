import AgentBarCore
import SwiftUI

struct AccountSectionView: View {
    let state: AccountState
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ProviderMark(kind: state.id.provider, isWorking: state.activity.isWorking)
                Text(state.account.name).fontWeight(.semibold).lineLimit(1)
                if let plan = state.account.plan {
                    Text(plan).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 3)
                if state.activity.isWorking {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("\(state.activity.workingCount) working").font(.system(size: 10)).monospacedDigit()
                }
            }
            if let snapshot = state.snapshot(at: now), !snapshot.windows.isEmpty {
                VStack(spacing: 7) {
                    ForEach(snapshot.windows) { window in
                        UsageWindowRow(window: window, now: now)
                    }
                }
            } else if state.usageError == nil {
                Text(state.isRefreshing ? "Loading usage…" : "No usage data")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let status = DisplayFormat.status(state, now: now) {
                Text(status).font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(state.usage.map { DisplayFormat.date($0.capturedAt) } ?? status)
            }
            if !state.activity.sessions.isEmpty {
                VStack(spacing: 5) {
                    ForEach(state.activity.sessions) { session in
                        SessionRow(session: session, now: now)
                    }
                }
            }
            Text(tokenSummary)
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private var tokenSummary: String {
        let today = Calendar.current.startOfDay(for: now)
        let start = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? now
        let todayTokens = state.statistics.days.filter { $0.day >= today && $0.day < tomorrow }.reduce(0) { $0 + $1.total.total }
        let weekTokens = state.statistics.days.filter { $0.day >= start && $0.day < tomorrow }.reduce(0) { $0 + $1.total.total }
        return "Tokens  \(DisplayFormat.tokens(todayTokens)) today · \(DisplayFormat.tokens(weekTokens)) in 7d"
    }
}
