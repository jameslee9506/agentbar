import AgentBarCore
import Foundation

actor CodexStatisticsService {
    private let cache: DiskCache
    private let clock: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar
    private let rollouts: CodexRolloutUsage
    private let scheduler = CodexStatisticsScheduler()
    private var homes: [String: CodexHomeStatistics] = [:]

    init(cache: DiskCache, clock: @escaping @Sendable () -> Date, calendar: @escaping @Sendable () -> Calendar, rollouts: CodexRolloutUsage) {
        self.cache = cache
        self.clock = clock
        self.calendar = calendar
        self.rollouts = rollouts
    }

    func statistics(for account: Account, days: Int) async -> UsageStatistics {
        let key = account.home.standardizedFileURL.path
        let calendar = calendar()
        let worker: CodexHomeStatistics
        if let existing = homes[key] { worker = existing }
        else {
            worker = CodexHomeStatistics(home: account.home, cache: cache, calendar: calendar, clock: clock, rollouts: rollouts)
            homes[key] = worker
        }
        return await scheduler.run { await worker.statistics(days: days, calendar: calendar) }
    }
}
