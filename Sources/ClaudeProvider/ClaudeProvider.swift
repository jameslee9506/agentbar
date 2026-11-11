import AgentBarCore
import Foundation

/// Monitors the Claude Code accounts on this machine.
public struct ClaudeProvider: AccountProvider {
    public let kind = ProviderKind.claude
    private let discovery: AccountDiscovery
    private let usageService: UsageService
    private let sessions: SessionMonitor
    private let statisticsStore: StatisticsStore

    public init() {
        let root = FileManager.default.homeDirectoryForCurrentUser
        self.init(
            homeRoot: root,
            processes: SystemProcessInspector(),
            credentials: KeychainCredentialReader(defaultHome: root.appendingPathComponent(".claude")),
            transport: UsageTransport(),
            clock: { Date() },
            cacheDirectory: DiskCache.defaultDirectory
        )
    }

    init(
        homeRoot: URL,
        processes: any ProcessListing,
        credentials: any CredentialReading,
        transport: any UsageTransporting,
        clock: @escaping @Sendable () -> Date,
        cacheDirectory: URL,
        calendar: @escaping @Sendable () -> Calendar = { Calendar.current },
        pollInterval: Duration = .seconds(2)
    ) {
        let cache = DiskCache(directory: cacheDirectory)
        discovery = AccountDiscovery(root: homeRoot, credentials: credentials)
        usageService = UsageService(credentials: credentials, transport: transport, clock: clock, cache: cache)
        sessions = SessionMonitor(root: homeRoot, processes: processes, pollInterval: pollInterval)
        statisticsStore = StatisticsStore(cache: cache, clock: clock, calendar: calendar)
    }

    public func accounts() async -> [Account] { await discovery.accounts() }

    public func cachedUsage(for account: Account) async -> UsageSnapshot? {
        await usageService.cachedUsage(for: account)
    }

    public func usage(for account: Account) async throws(UsageError) -> UsageSnapshot {
        try await usageService.usage(for: account)
    }

    public func activity(for accounts: [Account]) -> AsyncStream<[AccountID: AccountActivity]> {
        sessions.activity(for: accounts)
    }

    public func statistics(for account: Account, days: Int) async -> UsageStatistics {
        await statisticsStore.statistics(for: account, days: days)
    }
}
