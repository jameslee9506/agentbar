import AgentBarCore
import Foundation

struct AccountState: Identifiable, Sendable {
    var account: Account
    var usage: UsageSnapshot?
    var usageError: UsageError?
    var activity: AccountActivity = .none
    var statistics: UsageStatistics = .empty
    var lastSuccessfulRefresh: Date?
    var lastAttempt: Date?
    var retryAfter: Date?
    var isRefreshing = false

    var id: AccountID { account.id }
    var isStale: Bool { usage != nil && (usageError != nil || lastSuccessfulRefresh == nil) }

    /// Claude Code accounts before Codex accounts, each by name.
    static func defaultOrder(_ lhs: AccountState, _ rhs: AccountState) -> Bool {
        if lhs.id.provider != rhs.id.provider { return lhs.id.provider < rhs.id.provider }
        let order = lhs.account.name.localizedStandardCompare(rhs.account.name)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }

    func snapshot(at date: Date) -> UsageSnapshot? {
        usage?.rolledForward(to: date)
    }

    func nextAutomaticRefresh(at date: Date) -> Date {
        max(date, lastAttempt?.addingTimeInterval(60) ?? date, retryAfter ?? date)
    }

    func canRefresh(at date: Date, manually: Bool) -> Bool {
        guard !isRefreshing, retryAfter.map({ $0 <= date }) ?? true else { return false }
        return manually || lastAttempt.map { date.timeIntervalSince($0) >= 60 } ?? true
    }

    mutating func accept(_ snapshot: UsageSnapshot) {
        if usage == nil || snapshot.capturedAt >= usage!.capturedAt {
            usage = snapshot
        }
    }
}
