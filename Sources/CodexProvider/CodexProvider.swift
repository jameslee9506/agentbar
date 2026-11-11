import AgentBarCore
import Foundation

/// Monitors the Codex accounts on this machine.
public struct CodexProvider: AccountProvider {
    public let kind = ProviderKind.codex
    private let discovery: CodexAccounts
    private let usageService: CodexUsageService
    private let statisticsService: CodexStatisticsService
    private let processes: any ProcessListing
    private let rolloutUsage: CodexRolloutUsage
    private let pollInterval: Duration

    public init() {
        self.init(
            homeRoot: FileManager.default.homeDirectoryForCurrentUser,
            processes: SystemProcessInspector(),
            transport: CodexHTTPTransport(),
            clock: { Date() },
            cacheDirectory: DiskCache().directory
        )
    }

    init(
        homeRoot: URL,
        processes: any ProcessListing,
        transport: any CodexUsageTransport,
        clock: @escaping @Sendable () -> Date,
        cacheDirectory: URL,
        calendar: Calendar? = nil,
        currentCalendar: @escaping @Sendable () -> Calendar = { .current },
        pollInterval: Duration = .seconds(1)
    ) {
        let cache = DiskCache(directory: cacheDirectory)
        let rolloutUsage = CodexRolloutUsage()
        discovery = CodexAccounts(root: homeRoot)
        usageService = CodexUsageService(transport: transport, clock: clock, cache: cache, rollouts: rolloutUsage, processes: processes)
        statisticsService = CodexStatisticsService(cache: cache, clock: clock, calendar: { calendar ?? currentCalendar() }, rollouts: rolloutUsage)
        self.processes = processes
        self.rolloutUsage = rolloutUsage
        self.pollInterval = pollInterval
    }

    public func accounts() async -> [Account] { discovery.accounts() }

    public func cachedUsage(for account: Account) async -> UsageSnapshot? {
        await usageService.cachedUsage(for: account)
    }

    public func usage(for account: Account) async throws(UsageError) -> UsageSnapshot {
        try await usageService.usage(for: account)
    }

    public func activity(for accounts: [Account]) -> AsyncStream<[AccountID: AccountActivity]> {
        CodexSessionMonitor.stream(accounts: accounts, processes: processes, rollouts: rolloutUsage, interval: pollInterval)
    }

    public func statistics(for account: Account, days: Int) async -> UsageStatistics {
        await statisticsService.statistics(for: account, days: days)
    }
}
