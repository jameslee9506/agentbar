import AgentBarCore
import Foundation

actor StatisticsStore {
    private struct Scan {
        let id: UUID
        let start: Date
        let end: Date
        let calendar: Calendar
        let task: Task<UsageStatistics, Never>
    }

    private let cache: DiskCache
    private let clock: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar
    private var homes: [String: HomeStatistics] = [:]
    private var scans: [String: Scan] = [:]
    private(set) var scansStarted = 0

    init(cache: DiskCache, clock: @escaping @Sendable () -> Date, calendar: @escaping @Sendable () -> Calendar) {
        self.cache = cache
        self.clock = clock
        self.calendar = calendar
    }

    func statistics(for account: Account, days: Int) async -> UsageStatistics {
        guard days > 0 else { return .empty }
        let calendar = calendar()
        let today = calendar.startOfDay(for: clock())
        guard let start = calendar.date(byAdding: .day, value: 1 - days, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return .empty }
        let key = account.home.standardizedFileURL.path
        if let active = scans[key] {
            let result = await active.task.value
            if active.calendar == calendar, active.start <= start, active.end >= end {
                return UsageStatistics(days: result.days.filter { $0.day >= start && $0.day < end })
            }
            if scans[key]?.id == active.id { scans[key] = nil }
            return await statistics(for: account, days: days)
        }
        let scanner = homes[key] ?? HomeStatistics(home: account.home, cache: cache)
        homes[key] = scanner
        scansStarted += 1
        let task = Task.detached(priority: .utility) { await scanner.scan(since: start, until: end, calendar: calendar) }
        let id = UUID()
        scans[key] = Scan(id: id, start: start, end: end, calendar: calendar, task: task)
        let result = await task.value
        if scans[key]?.id == id { scans[key] = nil }
        return result
    }
}
