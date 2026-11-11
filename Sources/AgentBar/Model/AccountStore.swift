import AgentBarCore
import Foundation
import Observation

@MainActor
@Observable
final class AccountStore {
    private(set) var states: [AccountID: AccountState] = [:]
    private(set) var hasDiscoveredAccounts = false

    @ObservationIgnored private let providers: [any AccountProvider]
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let workEndDelay: TimeInterval
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var statisticsTask: Task<Void, Never>?
    @ObservationIgnored private var cacheTasks: [AccountID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingCacheReads: Set<AccountID> = []
    @ObservationIgnored private var usageTasks: [AccountID: Task<Void, Never>] = [:]
    @ObservationIgnored private var cooldowns: [AccountID: UsageCooldown] = [:]
    @ObservationIgnored private var activityTasks: [ProviderKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var workEndTasks: [AccountID: Task<Void, Never>] = [:]
    @ObservationIgnored private var workEndGenerations: [AccountID: UUID] = [:]
    @ObservationIgnored private var generations: [ProviderKind: UUID] = [:]
    @ObservationIgnored private var accountGenerations: [AccountID: UUID] = [:]
    @ObservationIgnored private var stopped = false

    init(
        providers: [any AccountProvider],
        now: @escaping () -> Date = Date.init,
        workEndDelay: TimeInterval = 3
    ) {
        self.providers = providers
        self.now = now
        self.workEndDelay = workEndDelay
    }

    var accounts: [AccountState] {
        states.values.sorted {
            if $0.id.provider != $1.id.provider { return $0.id.provider < $1.id.provider }
            let order = $0.account.name.localizedStandardCompare($1.account.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    var workingCount: Int { states.values.reduce(0) { $0 + $1.activity.workingCount } }
    var isRefreshing: Bool { states.values.contains(where: \.isRefreshing) }

    func refresh(reason: RefreshReason) async {
        guard !stopped else { return }
        if reason.discoversAccounts { await discoverAccounts() }
        await refreshUsage(for: Array(states.keys), reason: reason)
        await loadStatistics()
    }

    func stop() {
        stopped = true
        discoveryTask?.cancel()
        statisticsTask?.cancel()
        cacheTasks.values.forEach { $0.cancel() }
        usageTasks.values.forEach { $0.cancel() }
        activityTasks.values.forEach { $0.cancel() }
        workEndTasks.values.forEach { $0.cancel() }
        activityTasks.removeAll()
        cacheTasks.removeAll()
        pendingCacheReads.removeAll()
        usageTasks.removeAll()
        workEndTasks.removeAll()
        workEndGenerations.removeAll()
        for id in states.keys { states[id]?.isRefreshing = false }
    }

    private func discoverAccounts() async {
        if let discoveryTask {
            await discoveryTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: (ProviderKind, [Account]).self) { group in
                for provider in providers {
                    group.addTask { (provider.kind, await provider.accounts()) }
                }
                for await (kind, accounts) in group {
                    guard !Task.isCancelled, !stopped else { continue }
                    reconcile(accounts: accounts, kind: kind)
                }
            }
            hasDiscoveredAccounts = true
        }
        discoveryTask = task
        await task.value
        discoveryTask = nil
    }

    private func reconcile(accounts: [Account], kind: ProviderKind) {
        let oldIDs = Set(states.keys.filter { $0.provider == kind })
        let newIDs = Set(accounts.map(\.id))
        for id in oldIDs.subtracting(newIDs) {
            cacheTasks.removeValue(forKey: id)?.cancel()
            pendingCacheReads.remove(id)
            usageTasks.removeValue(forKey: id)?.cancel()
            states.removeValue(forKey: id)
            accountGenerations.removeValue(forKey: id)
            workEndTasks.removeValue(forKey: id)?.cancel()
            workEndGenerations.removeValue(forKey: id)
        }
        cooldowns = cooldowns.filter { states[$0.key] != nil || $0.value.isActive(at: now()) }
        for account in accounts {
            if states[account.id] != nil {
                states[account.id]?.account = account
            } else {
                let cooldown = cooldowns[account.id]
                var state = AccountState(account: account)
                state.lastAttempt = cooldown?.lastAttempt
                state.retryAfter = cooldown?.retryAfter
                if let deadline = cooldown?.retryAfter, deadline > now() {
                    state.usageError = .rateLimited(retryAfter: deadline.timeIntervalSince(now()))
                }
                states[account.id] = state
                accountGenerations[account.id] = UUID()
            }
            hydrateCache(for: account.id)
        }
        if oldIDs != newIDs || activityTasks[kind] == nil {
            restartActivity(kind: kind, accounts: accounts)
        }
    }

    private func restartActivity(kind: ProviderKind, accounts: [Account]) {
        activityTasks.removeValue(forKey: kind)?.cancel()
        let generation = UUID()
        generations[kind] = generation
        guard let provider = provider(for: kind), !accounts.isEmpty else { return }
        let stream = provider.activity(for: accounts)
        activityTasks[kind] = Task { [weak self] in
            for await activity in stream {
                guard !Task.isCancelled, let self,
                      !self.stopped, self.generations[kind] == generation else { break }
                self.applyActivity(activity, kind: kind)
            }
        }
    }

    func applyActivity(_ activity: [AccountID: AccountActivity], kind: ProviderKind) {
        guard !stopped else { return }
        for (id, value) in activity where id.provider == kind {
            guard let previous = states[id]?.activity, previous != value else { continue }
            states[id]?.activity = value
            hydrateCache(for: id)
            if value.isWorking {
                workEndTasks.removeValue(forKey: id)?.cancel()
                workEndGenerations.removeValue(forKey: id)
            } else if previous.isWorking {
                scheduleWorkEndRefresh(for: id)
            }
        }
    }

    private func scheduleWorkEndRefresh(for id: AccountID) {
        workEndTasks.removeValue(forKey: id)?.cancel()
        let generation = UUID()
        workEndGenerations[id] = generation
        workEndTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if workEndGenerations[id] == generation {
                    workEndTasks[id] = nil
                    workEndGenerations[id] = nil
                }
            }
            do {
                try await Task.sleep(for: .seconds(workEndDelay))
                // Recheck after sleeping: a refresh may have happened during the delay.
                while let state = states[id], !state.activity.isWorking {
                    guard !Task.isCancelled, !stopped else { return }
                    if state.isRefreshing {
                        try await Task.sleep(for: .seconds(1))
                        continue
                    }
                    let delay = state.nextAutomaticRefresh(at: now()).timeIntervalSince(now())
                    if delay > 0 {
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    }
                    guard !Task.isCancelled, !stopped else { return }
                    await refreshUsage(for: [id], reason: .workEnded)
                    await loadStatistics()
                    break
                }
            } catch { /* Cancellation ends the pending refresh. */ }
        }
    }

    func waitForWorkEndRefreshes() async {
        for task in workEndTasks.values { await task.value }
    }

    private func hydrateCache(for id: AccountID) {
        guard !stopped, let account = states[id]?.account,
              let provider = provider(for: id.provider), let generation = accountGenerations[id] else { return }
        if cacheTasks[id] != nil {
            pendingCacheReads.insert(id)
            return
        }
        cacheTasks[id] = Task { [weak self] in
            var nextAccount: Account? = account
            while let account = nextAccount {
                let snapshot = await provider.cachedUsage(for: account)
                guard !Task.isCancelled, let self, !stopped, accountGenerations[id] == generation else { return }
                if let snapshot { states[id]?.accept(snapshot) }
                // Changes during a read collapse into one trailing read for this account.
                if pendingCacheReads.remove(id) != nil {
                    nextAccount = states[id]?.account
                } else {
                    cacheTasks[id] = nil
                    return
                }
            }
        }
    }

    func waitForCacheHydration() async {
        while !cacheTasks.isEmpty {
            for task in cacheTasks.values { await task.value }
        }
    }

    func refreshUsage(for ids: [AccountID], reason: RefreshReason) async {
        guard !stopped else { return }
        var tasks: [Task<Void, Never>] = []
        for id in ids {
            guard usageTasks[id] == nil, let state = states[id], state.canRefresh(at: now(), manually: reason == .manual),
                  let provider = provider(for: id.provider), let generation = accountGenerations[id] else { continue }
            let attemptedAt = now()
            states[id]?.lastAttempt = attemptedAt
            states[id]?.isRefreshing = true
            cooldowns[id] = UsageCooldown(lastAttempt: attemptedAt, retryAfter: state.retryAfter)
            let task = Task { [weak self] in
                let result: Result<UsageSnapshot, UsageError>
                do {
                    result = .success(try await provider.usage(for: state.account))
                } catch {
                    result = .failure(error as? UsageError ?? .unavailable("Could not refresh usage"))
                }
                guard !Task.isCancelled, let self, !stopped, accountGenerations[id] == generation else { return }
                usageTasks[id] = nil
                states[id]?.isRefreshing = false
                switch result {
                case .success(let snapshot):
                    states[id]?.accept(snapshot)
                    states[id]?.usageError = nil
                    states[id]?.retryAfter = nil
                    cooldowns[id]?.retryAfter = nil
                    states[id]?.lastSuccessfulRefresh = now()
                case .failure(let error):
                    states[id]?.usageError = error
                    if case .rateLimited(let interval) = error {
                        let delay = interval.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 300
                        let deadline = now().addingTimeInterval(delay)
                        states[id]?.retryAfter = deadline
                        cooldowns[id]?.retryAfter = deadline
                    }
                }
            }
            usageTasks[id] = task
            tasks.append(task)
        }
        for task in tasks { await task.value }
    }

    func loadStatistics() async {
        if let statisticsTask {
            await statisticsTask.value
            return
        }
        let task = Task(priority: .utility) { [weak self] in
            guard let self, !stopped else { return }
            await withTaskGroup(of: (AccountID, UUID?, UsageStatistics).self) { group in
                for state in accounts {
                    guard let provider = provider(for: state.id.provider) else { continue }
                    let generation = accountGenerations[state.id]
                    group.addTask(priority: .utility) {
                        (state.id, generation, await provider.statistics(for: state.account, days: 90))
                    }
                }
                for await (id, generation, statistics) in group {
                    guard !Task.isCancelled, !stopped, accountGenerations[id] == generation else { continue }
                    states[id]?.statistics = statistics
                }
            }
        }
        statisticsTask = task
        await task.value
        statisticsTask = nil
    }

    private func provider(for kind: ProviderKind) -> (any AccountProvider)? {
        providers.first { $0.kind == kind }
    }
}
